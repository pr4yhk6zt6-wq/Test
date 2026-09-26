# Simulator - Test without iOS devices

This simulator proves the remote controller protocol works end-to-end without needing jailbroken iPhones.

## What it simulates

- **receiver_simulator.py**: Simulates iPhone B (ReceiverB)
  - Daemon: TCP server 0.0.0.0:9944
  - Tweak: parses packets and maps to GCController elements
  - Game: displays what Stardew Valley would see via GCController API

- **test_client.py**: Simulates iPhone A (ControllerA)
  - Sends RemoteControllerPacket at 60Hz with test sequence

## How to run

### Terminal 1: Start receiver (iPhone B)

```bash
python3 Simulator/receiver_simulator.py
```

You should see:
```
[SIM] ReceiverB Simulator listening on 0.0.0.0:9944
=== Remote Controller Simulator (iPhone B) ===
Packets received: 0...
Listening on 0.0.0.0:9944...
```

### Terminal 2: Start client (iPhone A)

```bash
python3 Simulator/test_client.py 127.0.0.1
```

You should see client sending test inputs, and simulator displaying them:

```
[CLIENT] Connected, sending test inputs...
[CLIENT] Sent Move Left: seq=2
[SIM] Left Stick X=-1.00 Y=0.00 -> extendedGamepad.leftThumbstick x=-1.00 y=0.00
...
[CLIENT] Sent A Button: seq=8 -> Buttons: A -> extendedGamepad.A PRESSED
...
```

### Test all required buttons

The test sequence covers all requirements:

- Left Stick: Move Left/Right/Up/Down + circular 60Hz
- Right Stick: Right Stick test
- D-pad: DPad Up
- A/B/X/Y: A Button, B Button, X Button, Y Button
- L1/R1: L1, R1
- L2/R2: L2 Trigger 0.8, R2 Trigger 0.9 (analog)
- Menu/View: Menu, View
- L3/R3: included in bitmask

All should show PASS.

## Protocol

- Packet size: 60 bytes (little-endian)
- Structure: magic (0x52435044), version, timestamp_ms, sequence, leftX, leftY, rightX, rightY, dpadX, dpadY, buttons (bitmask), leftTrigger, rightTrigger, reserved
- Transport: TCP with 4-byte length prefix (little-endian)

## Why this proves architecture

- The real iPhone B daemon does exactly same: TCP server 9944, parses 60-byte packet, forwards to Unix socket clients (tweaks)
- The real tweak does same mapping: packet -> GCController elements -> valueChangedHandler
- If simulator can receive and map correctly, real daemon+tweak will too
- Only difference is real tweak hooks GCController.framework via MobileSubstrate, which is proven to work by MFiWrapper/ControllersForAll/nControl

## Next steps for real hardware

1. Build ControllerA.ipa via Xcode (or use GitHub Actions)
2. Build ReceiverB.deb via Theos (or use Python fallback DEB in ReceiverB/packages/)
3. Install on 2 iPhones same Wi-Fi
4. Connect and test Stardew Valley

See docs/TEST_REPORT_v2.md for detailed results.
