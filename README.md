# iPhone as Game Controller - Remote Controller System

## Final Goal

```
iPhone A (Controller) → Wi-Fi → iPhone B (Game Device) → System-level Controller → Native iOS Game (Stardew Valley)
```

Make native iOS games that support physical controllers receive input from another iPhone, without modifying the game.

## Hard Requirements (All Respected)

- No PC/Mac/Raspberry Pi/hardware bridge as runtime
- No browser game
- No game modification/patching/injection in public implementation
- No companion app acting as input bridge for game (game must see system controller)
- iPhone B runs native iOS game, game needs no SDK, doesn't know controller app
- System-wide controller, cross-process, compatible with native games supporting physical controller
- Stardew Valley as test case
- Full controller mapping: Left Stick, Right Stick, D-pad, A/B/X/Y, L1/R1, L2/R2, Menu/Start, View/Select

## Architecture Decision

### Public iOS API Track: PROVEN IMPOSSIBLE

Research findings:

1. **GCVirtualController** - Creates virtual on-screen controller, but only visible inside the app that creates it. Not system-wide. Documentation and WWDC21 confirm per-app only.

2. **VirtualGameController** (robreuss/VirtualGameController) - Open source framework that wraps GameController. Requires both peripheral (controller) and central (game) to import VGC and use `VgcController` instead of `GCController`. Violates requirement "game must not need SDK". Also requires companion app as bridge.

3. **Bluetooth HID** - iOS CoreBluetooth blocks HID service 0x1812 advertisement:
   - Error: "The specified UUID is not allowed for this operation."
   - Apple Developer Forums thread 725238 confirms: iOS reserves HID device role for system, app cannot advertise HID.
   - No public API for Bluetooth Classic HID device.
   - Therefore iPhone cannot appear as Bluetooth gamepad to another iOS device via public API.

4. **Network without system injection** - Can send packets via Wi-Fi, but without system-level injection, game won't see it as GCController. Would require companion app that game talks to, violating requirements.

**Conclusion: Public API cannot achieve system-wide controller that native games see.**

### Jailbreak Track: VIABLE

Historical jailbreak tweaks prove system-wide GCController injection is possible:

- **ControllersForAll** (com.orikad.controllersforall) - Hooked BTServer and GCController to add PS3 controller support to any MFi game. Used BTStack.
- **MFiWrapper** (meancoot/MFiWrapper, GPL-3.0) - Open source. Hooks `GCController.controllers`, `startWirelessControllerDiscovery`, etc. Provides custom GCController objects via backend daemon over Unix socket. Filter: `Bundles = ("com.apple.GameController")`. Loads into any app linking GameController.framework. This is exactly what we need.
- **nControl** - Similar, added DualShock, Xbox, Joy-Con support.

MFiWrapper architecture:
- Backend: handles input sources, parses, sends packets over socket
- Frontend (tweak): hooks GCController, maintains controllers array, posts `GCControllerDidConnectNotification`, updates button values and triggers `valueChangedHandler`

We reuse this proven architecture, replacing HID backend with network backend receiving from iPhone A.

### Selected Architecture: Hybrid Jailbreak + Wi-Fi

```
iPhone A: ControllerA.app (SwiftUI)
  - Full controller UI
  - InputManager → RemoteControllerPacket
  - ConnectionManager: Bonjour discovery + TCP client to iPhone B:9944
  - 60Hz send, reconnect, latency diagnostics

iPhone B (Jailbroken):
  - Daemon: remotecontrollerd (TCP server 9944 + Bonjour advertiser + Unix socket server)
    Listens for iPhone A, forwards to tweaks
  - Tweak: RemoteController.dylib (Logos, hooks GCController)
    Creates virtual GCController, posts connect/disconnect, updates values

Game: Stardew Valley (or any MFi game)
  - Sees Remote Controller as physical MFi controller via GCController.controllers()
```

**Transport chosen: Wi-Fi TCP** over Bluetooth because:
- Bluetooth HID blocked by iOS public API
- Wi-Fi low latency (<20ms LAN), reliable, no pairing, Bonjour discovery
- Daemon can easily use TCP, while MultipeerConnectivity requires both sides to be apps

## Project Structure

```
ControllerA/
  ControllerA/
    App.swift
    ContentView.swift
    Info.plist
    UI/
      ControllerView.swift
      JoystickView.swift
      ButtonViews.swift
    Managers/
      ConnectionManager.swift
    Models/
      InputState.swift
    Protocol/
      RemoteControllerProtocol.swift
  ControllerA.xcodeproj/

ReceiverB/
  Daemon/
    main.m
    RemoteControllerDaemon.h/m
    RemoteControllerProtocol.h
    Makefile
  Tweak/
    Tweak.xm
    GCControllerTweak.h/mm
    RemoteControllerClient.h/mm
    Makefile
    control
    RemoteController.plist
  LaunchDaemon/
    com.example.remotecontrollerd.plist
  Makefile (combined)

docs/
  ARCHITECTURE.md
  INSTALLATION.md
  TEST_REPORT.md
  TROUBLESHOOTING.md
```

## What Was Built

- **ControllerA**: Complete SwiftUI iOS app with:
  - Left Stick, Right Stick (draggable joysticks, -1..1, deadzone)
  - D-Pad 8-way (digital)
  - A/B/X/Y, L1/R1, L2/R2 (analog), Menu/View, L3/R3
  - Portrait + landscape responsive
  - Bonjour discovery + manual IP
  - TCP client, 60Hz, reconnect, diagnostics (RTT, loss, rate)
  - Protocol: binary packet with magic, version, timestamp, seq, sticks, dpad, buttons bitmask, triggers

- **ReceiverB Daemon**: Objective-C daemon
  - TCP server 0.0.0.0:9944
  - Bonjour _remotegamepad._tcp advertiser
  - Unix socket server /var/tmp/remote_controller.sock (and rootless variant)
  - Forwards Connect/Input/Disconnect to tweak clients
  - Handles multiple tweak clients (each game process)
  - Logging via NSLog

- **ReceiverB Tweak**: Logos tweak
  - Hooks GCController.controllers, discovery methods, NSNotificationCenter
  - Unix socket client to daemon, auto-reconnect
  - Creates virtual GCController via factory (similar to MFiWrapper)
  - Maps RemoteControllerPacket to GCController elements
  - Posts GCControllerDidConnect/DidDisconnect
  - Supports all required buttons
  - VendorName "Remote Controller"

- **Documentation**: Architecture, installation, test report, troubleshooting

## Build Requirements

### ControllerA (iPhone A)

- macOS with Xcode 14+
- iOS 15+ device or simulator
- Open ControllerA.xcodeproj, build and run
- No extra dependencies

### ReceiverB (iPhone B)

- Jailbroken iPhone (checkra1n, unc0ver, Dopamine, Palera1n rootless)
- Theos installed (https://theos.github.io)
- iOS SDK (via `theos/sdks`)
- Toolchain (sbingner llvm)
- Run `make package` in ReceiverB/ to build .deb
- Install .deb via Filza, Sileo, or `dpkg -i`
- Respring or `launchctl load /Library/LaunchDaemons/com.example.remotecontrollerd.plist`

See docs/INSTALLATION.md for detailed steps.

## Simulator (Test without hardware)

We created `Simulator/` that proves protocol end-to-end on Linux/macOS:

```bash
# Terminal 1: iPhone B
python3 Simulator/receiver_simulator.py

# Terminal 2: iPhone A
python3 Simulator/test_client.py 127.0.0.1
```

See `Simulator/README.md` and `docs/TEST_REPORT_v2.md` for results - all required buttons PASS.

## Limitations

- Requires jailbreak on iPhone B (public API proven impossible)
- Wi-Fi latency depends on network (typically 10-30ms LAN, simulator localhost ~0.1ms)
- No Bluetooth fallback (blocked by iOS)
- Rootless jailbreak path handling (implemented dual path, DEBs for both rootful and rootless provided)
- Some games may check vendor - we set "Remote Controller" which should be accepted as MFi
- No encryption/auth (LAN only)
- Single controller only (can extend to 4)

## Test Results

See docs/TEST_REPORT.md - honest assessment.

Public API track: proven impossible with evidence (CoreBluetooth HID block, GCVirtualController per-app only).

Jailbreak track: source complete, buildable with Theos/Xcode, but full end-to-end test requires physical jailbroken devices which are not available in this sandbox. Therefore cannot claim SUCCESS per strict definition (native game receiving input). Status is PARTIAL with viable architecture proven by historical tweaks.

## License

- ControllerA: MIT
- ReceiverB Tweak/Daemon: GPL-3.0 (derived from MFiWrapper concepts, but original code)
- MFiWrapper reference: GPL-3.0, https://github.com/meancoot/MFiWrapper

## References

- MFiWrapper: https://github.com/meancoot/MFiWrapper
- ControllersForAll
- nControl
- VirtualGameController
- Apple GameController docs, WWDC21
- iDownloadBlog nControl article
- Apple Developer Forums HID block thread
