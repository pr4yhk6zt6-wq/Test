#!/usr/bin/env python3
"""
เซิร์ฟเวอร์จำลอง OpenRouter สำหรับการทดสอบแบบ end-to-end ในแซนด์บล็อก

จำลองพฤติกรรมที่โหดกว่าของจริงเพื่อทดสอบโค้ดฝั่งแอป:
  • ส่ง SSE แบบ "หั่นกลาง JSON" — การันตีว่าไคลเอนต์ต้อง buffer บรรทัดให้ถูก
  • ส่ง comment keep-alive แบบ ": OPENROUTER PROCESSING"
  • ส่ง tool_calls ที่ arguments ถูกแบ่งเป็นหลาย chunk + usage chunk ท้ายสุด + [DONE]
  • ตอบ 429 หนึ่งครั้งแล้วค่อยสำเร็จ (ทดสอบ retry + backoff)
  • ตอบ 404 / 401 (ต้องไม่ retry)
  • /react/ และ /react-shell/: จำลอง ReAct 2 รอบ (รอบแรกขอเรียก tool, รอบสองตอบด้วยข้อความสุดท้าย)
  • /loop-forever/: ขอเรียก tool ทุกรอบ เพื่อทดสอบเพดาน 20 รอบ

นับจำนวนคำขอไว้ที่ /tmp/mock_openrouter_counts.json เพื่อให้การทดสอบยืนยันได้ว่า
ไคลเอนต์ "ลองซ้ำ" หรือ "ไม่ลองซ้ำ" ตามที่ควร

ใช้งาน:  python3 mock_openrouter_server.py <port>
"""

import json
import sys
import threading
import time
import socketserver
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COUNTS = {}
COUNTS_LOCK = threading.Lock()
COUNTS_PATH = "/tmp/mock_openrouter_counts.json"
AUTH_PATH = "/tmp/mock_openrouter_auth.json"
AUTH_LOCK = threading.Lock()
BODY_PATH = "/tmp/mock_openrouter_body.json"
BODY_LOCK = threading.Lock()


def bump(path: str) -> int:
    with COUNTS_LOCK:
        COUNTS[path] = COUNTS.get(path, 0) + 1
        try:
            with open(COUNTS_PATH, "w") as handle:
                json.dump(COUNTS, handle)
        except OSError:
            pass
        return COUNTS[path]


def record_auth(path: str, authorization) -> None:
    """บันทึกหัวข้อ Authorization ที่ได้รับจริง (ใช้ทดสอบว่าคีย์ถูกทำความสะอาดก่อนส่ง)"""
    entry = {"path": path, "authorization": authorization if authorization is not None else ""}
    with AUTH_LOCK:
        try:
            with open(AUTH_PATH) as handle:
                entries = json.load(handle)
                if not isinstance(entries, list):
                    entries = []
        except (OSError, ValueError):
            entries = []
        entries.append(entry)
        try:
            with open(AUTH_PATH, "w") as handle:
                json.dump(entries[-50:], handle)
        except OSError:
            pass


def record_body(path: str, body) -> None:
    """บันทึกข้อเท็จจริงของคำขอที่ได้รับ (ใช้ตรวจว่ารูป payload ที่แอปส่งถูกต้อง)"""
    messages = body.get("messages") if isinstance(body, dict) else None
    if not isinstance(messages, list):
        messages = []
    tools = body.get("tools") if isinstance(body, dict) else None
    provider = body.get("provider") if isinstance(body, dict) else None
    tool_messages = [m for m in messages if isinstance(m, dict) and m.get("role") == "tool"]
    summary = {
        "path": path,
        "has_tools": isinstance(tools, list) and len(tools) > 0,
        "tool_count": len(tools) if isinstance(tools, list) else 0,
        "parallel_tool_calls_present": bool(isinstance(body, dict) and "parallel_tool_calls" in body),
        "provider_require_parameters": bool(isinstance(provider, dict) and provider.get("require_parameters") is True),
        "tool_message_count": len(tool_messages),
        "tool_messages_have_name_field": any("name" in m for m in tool_messages),
        "tool_messages_have_empty_content": any(not str(m.get("content") or "").strip() for m in tool_messages),
    }
    with BODY_LOCK:
        try:
            with open(BODY_PATH) as handle:
                entries = json.load(handle)
                if not isinstance(entries, list):
                    entries = []
        except (OSError, ValueError):
            entries = []
        entries.append(summary)
        try:
            with open(BODY_PATH, "w") as handle:
                json.dump(entries[-50:], handle)
        except OSError:
            pass


def provider_error_body(raw_detail: str) -> dict:
    """รูปเดียวกับที่ OpenRouter ตอบเมื่อผู้ให้บริการปลายทางปฏิเสธคำขอ"""
    return {"error": {"code": 400,
                      "message": "Provider returned error",
                      "metadata": {"provider_name": "MockProvider", "raw": raw_detail}}}


def sse(payload: str) -> bytes:
    return ("data: " + payload + "\n\n").encode("utf-8")


def react_tool_call_chunks(tool_name: str, arguments_json: str, call_id: str = "call_react_1"):
    """tool_call ที่ arguments ถูกหั่นเป็น 3 chunk (จำลองการสตรีมของจริง)"""
    half = len(arguments_json) // 2
    parts = [arguments_json[:half], arguments_json[half:]]
    chunks = [
        '{"id":"gen-react","object":"chat.completion.chunk","model":"mock/tool-model",'
        '"choices":[{"index":0,"delta":{"role":"assistant","content":"ผมจะเรียก tool ให้ครับ "},'
        '"finish_reason":null}]}',
        '{"id":"gen-react","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"' + call_id + '",'
        '"type":"function","function":{"name":"' + tool_name + '","arguments":""}}]},"finish_reason":null}]}',
        '{"id":"gen-react","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":' + json.dumps(parts[0]) + '}}]},"finish_reason":null}]}',
        '{"id":"gen-react","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":' + json.dumps(parts[1]) + '}}]},"finish_reason":null}]}',
        '{"id":"gen-react","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
        sse_usage(prompt_tokens=120, completion_tokens=30, total=150),
    ]
    return chunks


def sse_usage(prompt_tokens: int, completion_tokens: int, total: int) -> str:
    return ('{"object":"chat.completion.chunk","usage":{"prompt_tokens":' + str(prompt_tokens) +
            ',"completion_tokens":' + str(completion_tokens) + ',"total_tokens":' + str(total) +
            ',"cost":0.0},"choices":[]}')


def conversation_has_tool_result(body) -> bool:
    """ตรวจว่าคำขอนี้มีผลลัพธ์ของ tool แนบมาหรือยัง (แปลว่าเป็นรอบที่สองของ ReAct)"""
    try:
        messages = body.get("messages") or []
    except AttributeError:
        return False
    for message in messages:
        if isinstance(message, dict) and message.get("role") == "tool":
            return True
    return False


def last_tool_result_text(body) -> str:
    """ดึงข้อความผลลัพธ์ของ tool ล่าสุดในคำขอ (ใช้ยืนยันว่าผลไหลกลับไปถึงเซิร์ฟเวอร์)"""
    try:
        messages = body.get("messages") or []
    except AttributeError:
        return ""
    for message in reversed(messages):
        if isinstance(message, dict) and message.get("role") == "tool":
            return str(message.get("content") or "")
    return ""


def count_tool_results(body) -> int:
    """นับจำนวนผลลัพธ์ของ tool ในคำขอ (ใช้จำลองหลายรอบการเรียก tool)"""
    try:
        messages = body.get("messages") or []
    except AttributeError:
        return 0
    return sum(1 for message in messages if isinstance(message, dict) and message.get("role") == "tool")


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


class FastThreadingHTTPServer(ThreadingHTTPServer):
    """ThreadingHTTPServer ที่ข้าม socket.getfqdn()

    เหตุผล: HTTPServer.server_bind() เรียก socket.getfqdn(host) ซึ่งทำ reverse DNS
    บน GitHub Actions runner (Azure) การค้นหานี้ "ค้างได้นานมาก" ทำให้เซิร์ฟเวอร์
    ขึ้นช้า/ไม่ขึ้นเลย ทั้งที่โปรเซสยังอยู่ — เจอจริงตอนรัน E2E บน macos-15
    """

    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = host
        self.server_port = port


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
        record_auth(self.path, self.headers.get("Authorization"))
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
        record_auth(self.path, self.headers.get("Authorization"))
        body = self._read_body()
        record_body(self.path, body)
        path = self.path

        if "/provider-400-always/" in path:
            bump("/provider-400-always")
            self._send_json(400, provider_error_body("upstream said: invalid request for this provider (mock)"))
            return

        if "/provider-400/" in path:
            attempt = bump("/provider-400")
            if attempt == 1:
                self._send_json(400, provider_error_body("upstream said: temporary provider failure (mock)"))
                return
            self._stream_text_reply(body)
            return

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

        if "/approve-every/" in path:
            # ใช้ทดสอบข้อกำหนดใหม่: "ต้องถามอนุมัติทุกครั้ง" — ขอเรียก execute_shell สองครั้งคนละรอบ
            # (ครั้งแรกผู้ใช้จะกดไม่อนุมัติ ครั้งที่สองต้องมีคำถามใหม่และทำงานได้จริง)
            bump("/approve-every")
            finished = count_tool_results(body)
            if finished == 0:
                self._stream_react_tool_call("execute_shell",
                                             json.dumps({"command": "echo approve-once-1", "timeout_seconds": 15}),
                                             call_id="call_ap_1")
            elif finished == 1:
                self._stream_react_tool_call("execute_shell",
                                             json.dumps({"command": "echo approve-once-2", "timeout_seconds": 15}),
                                             call_id="call_ap_2")
            else:
                self._stream_final_reply("ครั้งที่สองรันสำเร็จแล้วครับ: " + last_tool_result_text(body)[:200])
            return

        if "/react-shell/" in path:
            # รอบแรก: ขอเรียก execute_shell / รอบสอง: ตอบด้วยข้อความสุดท้าย
            bump("/react-shell")
            if conversation_has_tool_result(body):
                self._stream_final_reply("คำสั่งทำงานเสร็จแล้วครับ ผลลัพธ์คือ: " + last_tool_result_text(body)[:200])
            else:
                self._stream_react_tool_call("execute_shell",
                                             json.dumps({"command": "echo e2e-shell-ok", "timeout_seconds": 15}),
                                             call_id="call_shell_1")
            return

        if "/react/" in path:
            # ReAct สองรอบ: อ่านไฟล์จริงบนเครื่องแล้วสรุป — ใช้ทดสอบว่า tool ทำงานจริง
            bump("/react")
            if conversation_has_tool_result(body):
                self._stream_final_reply("อ่านไฟล์เรียบร้อยครับ สรุปว่า: " + last_tool_result_text(body)[:200])
            else:
                self._stream_react_tool_call("read_file",
                                             json.dumps({"path": "/tmp/e2e-react-note.txt"}),
                                             call_id="call_read_1")
            return

        if "/loop-forever/" in path:
            # ขอเรียก tool ทุกรอบ — ใช้ทดสอบเพดาน 20 รอบของ ReAct loop
            bump("/loop-forever")
            self._stream_react_tool_call("list_directory",
                                         json.dumps({"path": "/tmp"}),
                                         call_id="call_loop")
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

    def _stream_react_tool_call(self, tool_name: str, arguments_json: str, call_id: str):
        self._start_stream()
        for index, payload in enumerate(react_tool_call_chunks(tool_name, arguments_json, call_id)):
            self._write_raw(sse(payload))
            if index == 1:
                self._write_raw(b": keep-alive\n\n")
            time.sleep(0.004)
        self._write_raw(b"data: [DONE]\n\n")
        self._end_stream()

    def _stream_final_reply(self, text: str):
        self._start_stream()
        # แบ่งข้อความสุดท้ายเป็น 2 chunk เพื่อยืนยันว่าการสตรีมยังทำงานในรอบสุดท้าย
        head, tail = text[:len(text) // 2], text[len(text) // 2:]
        for piece in (head, tail):
            payload = ('{"id":"gen-final","choices":[{"index":0,"delta":{"content":' +
                       json.dumps(piece, ensure_ascii=False) + '},"finish_reason":null}]}')
            self._write_raw(sse(payload))
            time.sleep(0.004)
        self._write_raw(sse('{"id":"gen-final","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'))
        self._write_raw(sse(sse_usage(150, 40, 190)))
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
    server = FastThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"mock OpenRouter listening on {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
