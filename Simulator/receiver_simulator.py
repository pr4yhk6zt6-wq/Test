#!/usr/bin/env python3
"""
ReceiverB Simulator for testing without jailbroken iPhone
Simulates daemon + tweak + game

Listens on TCP 9944, receives RemoteControllerPacket from ControllerA,
parses and displays as virtual controller state, and simulates game input.

This proves the protocol and mapping work end-to-end, even without iOS.
"""

import socket
import struct
import threading
import time
import sys

RC_MAGIC = 0x52435044
RC_VERSION = 1
RC_PORT = 9944

# Buttons
BUTTONS = {
    1<<0: "A",
    1<<1: "B",
    1<<2: "X",
    1<<3: "Y",
    1<<4: "L1",
    1<<5: "R1",
    1<<6: "L2",
    1<<7: "R2",
    1<<8: "Menu",
    1<<9: "View",
    1<<10: "L3",
    1<<11: "R3",
}

class VirtualGamepad:
    def __init__(self):
        self.left_x = 0
        self.left_y = 0
        self.right_x = 0
        self.right_y = 0
        self.dpad_x = 0
        self.dpad_y = 0
        self.buttons = 0
        self.l2 = 0
        self.r2 = 0
        self.sequence = 0
        self.last_time = time.time()
        self.packet_count = 0

    def update(self, data):
        # Unpack: I I Q I f f f f f f I f f I = 60 bytes
        try:
            unpacked = struct.unpack('<IIQIffffffIffI', data)
            magic, version, timestamp, seq, lx, ly, rx, ry, dx, dy, btns, l2, r2, reserved = unpacked
            if magic != RC_MAGIC:
                print(f"[SIM] Invalid magic: {hex(magic)}")
                return False
            self.left_x = lx
            self.left_y = ly
            self.right_x = rx
            self.right_y = ry
            self.dpad_x = dx
            self.dpad_y = dy
            self.buttons = btns
            self.l2 = l2
            self.r2 = r2
            self.sequence = seq
            self.packet_count += 1
            now = time.time()
            dt = now - self.last_time
            self.last_time = now
            return True
        except Exception as e:
            print(f"[SIM] Parse error: {e}, data len {len(data)}")
            return False

    def display(self):
        # Clear screen
        sys.stdout.write("\033[H\033[J")
        print("=== Remote Controller Simulator (iPhone B) ===")
        print(f"Packets received: {self.packet_count}, Seq: {self.sequence}")
        print(f"Left Stick:  X={self.left_x:+.2f} Y={self.left_y:+.2f}")
        print(f"Right Stick: X={self.right_x:+.2f} Y={self.right_y:+.2f}")
        print(f"DPad:        X={self.dpad_x:+.0f} Y={self.dpad_y:+.0f}")
        print(f"L2: {self.l2:.2f} R2: {self.r2:.2f}")
        pressed = [name for bit, name in BUTTONS.items() if self.buttons & bit]
        print(f"Buttons: {', '.join(pressed) if pressed else 'None'} (raw {bin(self.buttons)})")
        print()
        print("Simulated Game Input (like Stardew Valley would see via GCController):")
        # Simulate GCController mapping
        print(f"  extendedGamepad.leftThumbstick: x={self.left_x:.2f} y={self.left_y:.2f}")
        print(f"  extendedGamepad.rightThumbstick: x={self.right_x:.2f} y={self.right_y:.2f}")
        print(f"  extendedGamepad.dpad: x={self.dpad_x:.0f} y={self.dpad_y:.0f}")
        for bit, name in BUTTONS.items():
            if name in ["A","B","X","Y","L1","R1","L3","R3","Menu","View"]:
                state = "PRESSED" if self.buttons & bit else "released"
                print(f"  extendedGamepad.{name}: {state}")
        print(f"  extendedGamepad.leftTrigger: {self.l2:.2f} (L2)")
        print(f"  extendedGamepad.rightTrigger: {self.r2:.2f} (R2)")
        print()
        print("This proves protocol works. In real jailbreak tweak, this would trigger")
        print("GCController valueChangedHandler and game would receive input.")
        print()
        print("Listening on 0.0.0.0:9944... Press Ctrl+C to exit")

def handle_client(conn, addr, gamepad):
    print(f"[SIM] New client from {addr}")
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
                if gamepad.update(pkt_data):
                    gamepad.display()
    except Exception as e:
        print(f"[SIM] Client error: {e}")
    finally:
        conn.close()
        print(f"[SIM] Client {addr} disconnected")

def main():
    gamepad = VirtualGamepad()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', RC_PORT))
    sock.listen(5)
    print(f"[SIM] ReceiverB Simulator listening on 0.0.0.0:{RC_PORT}")
    print(f"[SIM] Bonjour would advertise _remotegamepad._tcp on port {RC_PORT}")
    print(f"[SIM] Waiting for ControllerA to connect...")
    print(f"[SIM] To test, run ControllerA app or use test_client.py")
    print()
    gamepad.display()
    try:
        while True:
            conn, addr = sock.accept()
            threading.Thread(target=handle_client, args=(conn, addr, gamepad), daemon=True).start()
    except KeyboardInterrupt:
        print("\n[SIM] Exiting")
        sock.close()

if __name__ == "__main__":
    main()
