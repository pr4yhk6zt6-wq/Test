#!/usr/bin/env python3
"""
Test client that simulates iPhone A ControllerA app
Sends RemoteControllerPacket to ReceiverB simulator
"""

import socket
import struct
import time
import sys

RC_MAGIC = 0x52435044
RC_VERSION = 1
RC_PORT = 9944

def create_packet(seq, left_x=0, left_y=0, right_x=0, right_y=0, dpad_x=0, dpad_y=0, buttons=0, l2=0, r2=0):
    timestamp = int(time.time()*1000)
    return struct.pack('<IIQIffffffIffI',
        RC_MAGIC,
        RC_VERSION,
        timestamp,
        seq,
        left_x,
        left_y,
        right_x,
        right_y,
        dpad_x,
        dpad_y,
        buttons,
        l2,
        r2,
        0
    )

def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    print(f"[CLIENT] Connecting to {host}:{RC_PORT}")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, RC_PORT))
    print("[CLIENT] Connected, sending test inputs...")

    seq = 0
    try:
        # Test sequence simulating Stardew Valley gameplay
        tests = [
            ("Neutral", 0, 0, 0, 0, 0, 0, 0, 0, 0),
            ("Move Left", -1, 0, 0, 0, 0, 0, 0, 0, 0),
            ("Move Right", 1, 0, 0, 0, 0, 0, 0, 0, 0),
            ("Move Up", 0, 1, 0, 0, 0, 0, 0, 0, 0),
            ("Move Down", 0, -1, 0, 0, 0, 0, 0, 0, 0),
            ("Right Stick", 0, 0, 0.5, 0.5, 0, 0, 0, 0, 0),
            ("DPad Up", 0, 0, 0, 0, 0, 1, 0, 0, 0),
            ("A Button", 0, 0, 0, 0, 0, 0, 1<<0, 0, 0),
            ("B Button", 0, 0, 0, 0, 0, 0, 1<<1, 0, 0),
            ("X Button", 0, 0, 0, 0, 0, 0, 1<<2, 0, 0),
            ("Y Button", 0, 0, 0, 0, 0, 0, 1<<3, 0, 0),
            ("L1", 0, 0, 0, 0, 0, 0, 1<<4, 0, 0),
            ("R1", 0, 0, 0, 0, 0, 0, 1<<5, 0, 0),
            ("L2 Trigger", 0, 0, 0, 0, 0, 0, 0, 0.8, 0),
            ("R2 Trigger", 0, 0, 0, 0, 0, 0, 0, 0, 0.9),
            ("Menu", 0, 0, 0, 0, 0, 0, 1<<8, 0, 0),
            ("View", 0, 0, 0, 0, 0, 0, 1<<9, 0, 0),
            ("Combo A+Right", 0.7, 0.7, 0, 0, 0, 0, 1<<0, 0, 0),
        ]

        for name, lx, ly, rx, ry, dx, dy, btn, l2, r2 in tests:
            seq += 1
            pkt = create_packet(seq, lx, ly, rx, ry, dx, dy, btn, l2, r2)
            # Send with 4-byte length prefix
            sock.sendall(struct.pack('<I', len(pkt)) + pkt)
            print(f"[CLIENT] Sent {name}: seq={seq}")
            time.sleep(1)

        # Send 60Hz for 3 seconds
        print("[CLIENT] Sending 60Hz stream for 3s...")
        start = time.time()
        while time.time() - start < 3:
            seq += 1
            # Simulate circular left stick
            t = time.time() - start
            import math
            lx = math.cos(t*2) * 0.8
            ly = math.sin(t*2) * 0.8
            pkt = create_packet(seq, lx, ly, 0, 0, 0, 0, 0, 0, 0)
            sock.sendall(struct.pack('<I', len(pkt)) + pkt)
            time.sleep(1/60.0)

        print("[CLIENT] Test complete")

    except KeyboardInterrupt:
        pass
    finally:
        sock.close()

if __name__ == "__main__":
    main()
