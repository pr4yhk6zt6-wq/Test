#!/usr/bin/env python3
"""
RemoteControllerDaemon Python version
Fallback for jailbroken iPhones without compiled binary
Requires Python 3 on device (install via Sileo: Python 3.9+)

This implements same protocol as Objective-C daemon:
- TCP server 0.0.0.0:9944
- Bonjour advertisement via pybonjour or avahi (optional, not required for manual IP)
- Unix socket server /var/tmp/remote_controller.sock

Install: copy to /usr/bin/remotecontrollerd.py, chmod +x, and create LaunchDaemon that runs python3 /usr/bin/remotecontrollerd.py
"""

import socket
import struct
import threading
import os
import sys
import time

RC_MAGIC = 0x52435044
RC_PORT = 9944
RC_UNIX_SOCKET = "/var/tmp/remote_controller.sock"
RC_UNIX_SOCKET_ROOTLESS = "/var/jb/var/tmp/remote_controller.sock"

# Internal packet types
TYPE_CONNECT = 1
TYPE_DISCONNECT = 2
TYPE_INPUT = 3

class Daemon:
    def __init__(self):
        self.tcp_clients = []
        self.unix_clients = []
        self.has_controller = False
        self.handle = 1
        self.lock = threading.Lock()

    def start(self):
        print("[remotecontrollerd] Starting Python daemon")
        # Start Unix server
        threading.Thread(target=self.unix_server, daemon=True).start()
        # Start TCP server
        self.tcp_server()

    def unix_server(self):
        for path in [RC_UNIX_SOCKET, RC_UNIX_SOCKET_ROOTLESS]:
            try:
                os.unlink(path)
            except:
                pass
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
            except:
                pass

            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.bind(path)
                os.chmod(path, 0o777)
                sock.listen(10)
                print(f"[remotecontrollerd] Unix socket listening at {path}")
                # Use first successful path
                chosen = path
                break
            except Exception as e:
                print(f"[remotecontrollerd] Failed to bind {path}: {e}")
                continue
        else:
            print("[remotecontrollerd] Failed to bind any Unix socket")
            return

        while True:
            try:
                conn, _ = sock.accept()
                print(f"[remotecontrollerd] New Unix client")
                with self.lock:
                    self.unix_clients.append(conn)
                if self.has_controller:
                    self.send_connect(conn)
                threading.Thread(target=self.monitor_unix_client, args=(conn,), daemon=True).start()
            except Exception as e:
                print(f"[remotecontrollerd] Unix accept error: {e}")
                time.sleep(1)

    def monitor_unix_client(self, conn):
        try:
            while conn.recv(1):
                pass
        except:
            pass
        print("[remotecontrollerd] Unix client disconnected")
        with self.lock:
            if conn in self.unix_clients:
                self.unix_clients.remove(conn)
        conn.close()

    def tcp_server(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(('0.0.0.0', RC_PORT))
        sock.listen(5)
        print(f"[remotecontrollerd] TCP server listening on 0.0.0.0:{RC_PORT}")
        print(f"[remotecontrollerd] Bonjour _remotegamepad._tcp should be advertised (manual via DNS-SD if needed)")

        while True:
            conn, addr = sock.accept()
            print(f"[remotecontrollerd] New TCP client from {addr}")
            threading.Thread(target=self.handle_tcp_client, args=(conn, addr), daemon=True).start()

    def handle_tcp_client(self, conn, addr):
        buffer = b""
        try:
            while True:
                data = conn.recv(4096)
                if not data:
                    break
                buffer += data
                while len(buffer) >= 4:
                    pkt_len = struct.unpack('<I', buffer[:4])[0]
                    if len(buffer) < 4 + pkt_len:
                        break
                    pkt_data = buffer[4:4+pkt_len]
                    buffer = buffer[4+pkt_len:]
                    self.process_packet(pkt_data)
        except Exception as e:
            print(f"[remotecontrollerd] TCP client error {addr}: {e}")
        finally:
            conn.close()
            print(f"[remotecontrollerd] TCP client {addr} disconnected")
            if self.has_controller:
                self.has_controller = False
                self.send_disconnect()

    def process_packet(self, data):
        if len(data) < 60:
            print(f"[remotecontrollerd] Packet too small: {len(data)}")
            return
        magic = struct.unpack('<I', data[:4])[0]
        if magic != RC_MAGIC:
            print(f"[remotecontrollerd] Invalid magic {hex(magic)}")
            return
        if not self.has_controller:
            self.has_controller = True
            print("[remotecontrollerd] Controller connected, sending Connect to tweaks")
            self.send_connect_broadcast()
        self.send_input_broadcast(data)

    def make_internal_packet(self, ptype, handle, payload=b""):
        # Internal packet: size (I), type (I), handle (I), payload
        # For Connect: vendorName 64 bytes + presentControls I + analogControls I
        # For Input: 60 bytes RemoteControllerPacket
        # For Disconnect: empty
        if ptype == TYPE_CONNECT:
            vendor = b"Remote Controller\x00" + b"\x00"*47
            present = 0xFFFF
            analog = 0xFFFF
            inner = struct.pack('64sII', vendor, present, analog)
        elif ptype == TYPE_DISCONNECT:
            inner = b""
        elif ptype == TYPE_INPUT:
            inner = payload  # 60 bytes
        else:
            inner = b""

        total_size = 12 + len(inner)  # size field itself is 4, but we include header 12?
        # Actually per C struct: size, type, handle, union -> size = sizeof struct
        # We'll set size = 12 + len(inner) padded to struct size
        # For simplicity, use 12 + len(inner) as size, but receiver expects full struct size
        # Let's use fixed sizes: Connect = 12+72=84, Input=12+60=72, Disconnect=12
        if ptype == TYPE_CONNECT:
            size = 84
        elif ptype == TYPE_INPUT:
            size = 72
        else:
            size = 12

        header = struct.pack('<III', size, ptype, handle)
        # Pad to size
        packet = header + inner
        # Ensure length == size (pad if needed)
        if len(packet) < size:
            packet += b"\x00" * (size - len(packet))
        return packet

    def send_connect(self, conn):
        pkt = self.make_internal_packet(TYPE_CONNECT, self.handle)
        try:
            conn.sendall(pkt)
        except:
            pass

    def send_connect_broadcast(self):
        pkt = self.make_internal_packet(TYPE_CONNECT, self.handle)
        with self.lock:
            for c in self.unix_clients[:]:
                try:
                    c.sendall(pkt)
                except:
                    self.unix_clients.remove(c)

    def send_disconnect(self):
        pkt = self.make_internal_packet(TYPE_DISCONNECT, self.handle)
        with self.lock:
            for c in self.unix_clients[:]:
                try:
                    c.sendall(pkt)
                except:
                    self.unix_clients.remove(c)

    def send_input_broadcast(self, remote_packet):
        pkt = self.make_internal_packet(TYPE_INPUT, self.handle, remote_packet)
        with self.lock:
            for c in self.unix_clients[:]:
                try:
                    c.sendall(pkt)
                except:
                    self.unix_clients.remove(c)

if __name__ == "__main__":
    daemon = Daemon()
    daemon.start()
