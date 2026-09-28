#!/usr/bin/env python3
"""
เซิร์ฟเวอร์จำลอง OpenRouter สำหรับการทดสอบแบบ end-to-end ในแซนด์บล็อก

จำลองพฤติกรรมที่โหดกว่าของจริงเพื่อทดสอบโค้ดฝั่งแอป:
  • ส่ง SSE แบบ "หั่นกลาง JSON" — การันตีว่าไคลเอนต์ต้อง buffer บรรทัดให้ถูก
  • ส่ง comment keep-alive แบบ ": OPENROUTER PROCESSING"
  • ส่ง tool_calls ที่ arguments ถูกแบ่งเป็นหลาย chunk + usage chunk ท้ายสุด + [DONE]
  • ตอบ 429 หนึ่งครั้งแล้วค่อยสำเร็จ (ทดสอบ retry + backoff)
  • ตอบ 404 / 401 (ต้องไม่ retry)

นับจำนวนคำขอไว้ที่ /tmp/mock_openrouter_counts.json เพื่อให้การทดสอบยืนยันได้ว่า
ไคลเอนต์ "ลองซ้ำ" หรือ "ไม่ลองซ้ำ" ตามที่ควร

ใช้งาน:  python3 mock_openrouter_server.py <port>
"""

import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COUNTS = {}
COUNTS_LOCK = threading.Lock()
COUNTS_PATH = "/tmp/mock_openrouter_counts.json"


def bump(path: str) -> int:
    with COUNTS_LOCK:
        COUNTS[path] = COUNTS.get(path, 0) + 1
        try:
            with open(COUNTS_PATH, "w") as handle:
                json.dump(COUNTS, handle)
        except OSError:
            pass
        return COUNTS[path]


def sse(payload: str) -> bytes:
    return ("data: " + payload + "\n\n").encode("utf-8")


def tool_call_chunks():
    """tool_calls ที่ arguments ถูกแบ่งเป็น 4 chunk (แบบที่ OpenRouter ส่งจริง)"""
    return [
        '{"id":"gen-tools","object":"chat.completion.chunk","model":"mock/tool-model",'
        '"choices":[{"index":0,"delta":{"role":"assistant","content":null,'
        '"tool_calls":[{"index":0,"id":"call_abc","type":"function",'
        '"function":{"name":"read_file","arguments":""}}]},"finish_reason":null}]}',

        '{"id":"gen-tools","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":"{\\"pa"}}]},"finish_reason":null}]}',

        '{"id":"gen-tools","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":"th\\":\\"/var/mo"}}]},"finish_reason":null}]}',

        '{"id":"gen-tools","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":"bile/Documents/report.txt\\"}"}}]},"finish_reason":null}]}',

        '{"id":"gen-tools","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',

        '{"object":"chat.completion.chunk","usage":{"prompt_tokens":123,'
        '"completion_tokens":7,"total_tokens":130,"cost":0.00042,'
        '"prompt_tokens_details":{"cached_tokens":64}},"choices":[]}',

        "[DONE]",
    ]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # เงียบไว้
        pass

    # ---------- helpers ----------

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}

    def _send_json(self, status: int, payload: dict, extra_headers=None):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _start_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

    def _write_raw(self, data: bytes):
        """เขียนแบบ chunked encoding ทีละก้อนตามที่กำหนด (จำลองการหั่นกลาง JSON)"""
        self.wfile.write(("%X\r\n" % len(data)).encode("ascii") + data + b"\r\n")
        self.wfile.flush()

    def _end_stream(self):
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    # ---------- routes ----------

    def do_GET(self):
        if self.path.endswith("/models"):
            bump("/models")
            self._send_json(200, {
                "data": [
                    {"id": "mock/cheap-model:free", "name": "Mock Free", "context_length": 8192,
                     "pricing": {"prompt": "0", "completion": "0"},
                     "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
                     "supported_parameters": ["tools", "temperature"]},
                    {"id": "mock/vision-model", "name": "Mock Vision", "context_length": 128000,
                     "pricing": {"prompt": "0.000001", "completion": "0.000002"},
                     "architecture": {"input_modalities": ["text", "image"], "output_modalities": ["text"]},
                     "supported_parameters": ["tools", "temperature"]},
                    {"id": "mock/no-tools", "name": "Mock No Tools", "context_length": 4096,
                     "pricing": {"prompt": "0", "completion": "0"},
                     "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
                     "supported_parameters": ["temperature"]},
                    {"broken": True},  # รายการเสีย — ต้องถูกข้ามโดยไม่ทำให้ทั้งลิสต์พัง
                ]
            })
            return
        self._send_json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        body = self._read_body()
        path = self.path

        if "/notfound/" in path:
            bump("/notfound")
            self._send_json(404, {"error": {"message": "No endpoints found that support tool use"}})
            return

        if "/unauthorized/" in path:
            bump("/unauthorized")
            self._send_json(401, {"error": {"message": "No auth credentials found"}})
            return

        if "/retry/" in path:
            attempt = bump("/retry")
            if attempt == 1:
                self.send_response(429)
                self.send_header("Content-Type", "application/json")
                payload = json.dumps({"error": {"message": "Rate limit exceeded"}}).encode()
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            # ครั้งที่สองผ่าน
            self._stream_text_reply(body)
            return

        if "/tools/" in path:
            bump("/tools")
            self._stream_tool_calls()
            return

        if "/slowfail/" in path:
            bump("/slowfail")
            self._send_json(503, {"error": {"message": "Upstream provider unavailable"}})
            return

        # เส้นทางปกติ
        bump("/chat")
        self._stream_text_reply(body)

    # ---------- stream bodies ----------

    def _stream_text_reply(self, body: dict):
        self._start_stream()
        # 1) comment keep-alive (ไคลเอนต์ต้องข้ามให้ได้)
        self._write_raw(b": OPENROUTER PROCESSING\n\n")
        time.sleep(0.01)

        # 2) ส่ง chunk แรกแบบ "หั่นกลาง JSON" ออกเป็น 3 ก้อน
        first = sse('{"id":"gen-1","object":"chat.completion.chunk","model":"mock/cheap-model:free",'
                    '"choices":[{"index":0,"delta":{"role":"assistant","content":"สวัสดีครับ "},'
                    '"finish_reason":null}]}')
        third = max(1, len(first) // 3)
        self._write_raw(first[:third])
        time.sleep(0.01)
        self._write_raw(first[third:third * 2])
        time.sleep(0.01)
        self._write_raw(first[third * 2:])

        # 3) chunk ถัดไป
        self._write_raw(sse('{"id":"gen-1","choices":[{"index":0,'
                            '"delta":{"content":"ผมคือ Agent ทดสอบ"},"finish_reason":null}]}'))

        # 4) บรรทัดที่พัง + บรรทัดว่าง (ไคลเอนต์ต้องไม่ล้ม)
        self._write_raw(b"data: {\"broken\":\n")
        self._write_raw(b"\n")

        # 5) ปิดท้าย + usage + [DONE]
        self._write_raw(sse('{"id":"gen-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'))
        self._write_raw(sse('{"object":"chat.completion.chunk","usage":{"prompt_tokens":77,'
                            '"completion_tokens":12,"total_tokens":89,"cost":0.00031},'
                            '"choices":[]}'))
        self._write_raw(b"data: [DONE]\n\n")
        self._end_stream()

    def _stream_tool_calls(self):
        self._start_stream()
        for index, payload in enumerate(tool_call_chunks()):
            self._write_raw(sse(payload))
            if index == 1:
                self._write_raw(b": keep-alive\n\n")
            time.sleep(0.005)
        self._end_stream()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    with open(COUNTS_PATH, "w") as handle:
        json.dump({}, handle)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"mock OpenRouter listening on {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
