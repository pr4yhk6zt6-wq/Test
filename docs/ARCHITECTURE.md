# Remote Game Controller - Architecture

## Overview

```
iPhone A (Controller) 
  ↓ Wi-Fi TCP (Bonjour discovery)
iPhone B (Receiver - Jailbroken)
  ├─ Daemon: RemoteControllerDaemon (TCP server + Bonjour advertiser + Unix socket server)
  └─ Tweak: RemoteControllerTweak (GCController hook, creates virtual controller)
  ↓ System-wide GCController injection
Native iOS Game (e.g. Stardew Valley)
```

## Why Public API Fails

- `GCVirtualController`: only visible inside the app that creates it. Cannot be system-wide.
- `VirtualGameController` framework: requires game to import VGC and use `VgcController` instead of `GCController`. Violates "game must not need SDK".
- Bluetooth HID: iOS CoreBluetooth blocks HID service 0x1812 advertisement with error "The specified UUID is not allowed". No public API for classic Bluetooth HID peripheral. iPhone cannot appear as Bluetooth gamepad.
- Network without injection: sending packets to an app that forwards input requires companion app acting as bridge, which is prohibited and still wouldn't be seen as GCController by games.

**Conclusion: Public iOS API track is PROVEN IMPOSSIBLE for system-wide controller.**

## Why Jailbreak Track Works

Historical tweaks prove system-wide GCController injection is possible:

- **ControllersForAll** (com.orikad.controllersforall): hooked BTServer and GCController to add PS3 controller support.
- **MFiWrapper** (meancoot/MFiWrapper, GPL-3.0): open source tweak that hooks `GCController.controllers`, `startWirelessControllerDiscovery`, etc., and provides custom GCController objects via a backend daemon connected over Unix socket. Filter: `Bundles = ( "com.apple.GameController" )`. Loads into any app linking GameController.framework.
- **nControl**: similar, added support for DualShock, Xbox, Joy-Con.

MFiWrapper architecture:
- Backend: handles HID Bluetooth controllers, parses input, sends packets over socket.
- Frontend (tweak): hooks GCController, maintains `controllers` array, posts `GCControllerDidConnectNotification` / `DidDisconnect`, updates button values and triggers `valueChangedHandler`.

We reuse this proven architecture, but replace HID backend with network backend receiving from iPhone A.

## Components

### 1. ControllerA (iPhone A)

SwiftUI app, iOS 15+.

**UI Elements:**
- Left Stick: draggable circular joystick, returns x,y in -1..1, with deadzone.
- Right Stick: same.
- D-Pad: 4-way + diagonals, returns x,y in -1..1.
- ABXY: buttons.
- L1/R1, L2/R2: L1/R1 digital, L2/R2 analog (0..1) with digital threshold.
- Menu (Start) / View (Select).
- L3/R3 (optional stick clicks).

**Managers:**
- `InputManager`: aggregates UI state into `RemoteControllerPacket`.
- `ConnectionManager`: 
  - Bonjour browser for `_remotegamepad._tcp`
  - TCP client to iPhone B port 9944
  - Sends packet at 60Hz (configurable)
  - Reconnect with exponential backoff
  - Latency measurement: ping/pong RTT
- `Protocol`: binary packet with magic, version, timestamp, seq, sticks, dpad, buttons, triggers.

**Latency Handling:**
- Packet timestamp on A, B echoes back for RTT.
- Packet loss detection via sequence numbers.
- Diagnostic overlay showing RTT, packet loss, send rate.

### 2. ReceiverB

#### Daemon: RemoteControllerDaemon

- LaunchDaemon: `/Library/LaunchDaemons/com.example.remotecontrollerd.plist`, runs as `mobile`, keeps alive.
- Listens TCP 0.0.0.0:9944.
- Advertises Bonjour `_remotegamepad._tcp`.
- Unix socket server: `/var/tmp/remote_controller.sock` (world-writable for tweak clients) or `/var/mobile/Library/RemoteController/socket`.
- Protocol:
  - From A: binary `RemoteControllerPacket`
  - To tweak clients: `MFiWDataPacket`-like structure (Connect, InputState, Disconnect)
- Handles multiple tweak clients (each game process).
- On first connect from A: sends Connect packet to all tweak clients.
- On input: sends InputState to all clients.
- On disconnect from A: sends Disconnect.

Written in Objective-C++ / Swift with GCD for performance.

#### Tweak: RemoteControllerTweak

- Theos project, Logos.
- Plist filter: `Bundles = ( "com.apple.GameController" )` + `Executables = ( "StardewValley", ... )` fallback `Mode = Any` for GameController.
- Hooks:
  - `+[GCController controllers]` → returns merged array of real controllers + virtual.
  - `+[GCController startWirelessControllerDiscoveryWithCompletionHandler:]` → trigger our discovery if needed.
  - `+[GCController stopWirelessControllerDiscovery]`
  - `NSNotificationCenter` addObserver for connect notifications to trigger initial fetch.
- Maintains NSMutableArray `remoteControllers`.
- Connects to daemon Unix socket on init.
- On Connect packet: creates `GCController` subclass instance (similar to MFiWrapper's `GCControllerTweak`) with:
  - vendorName = "Remote Controller"
  - gamepad + extendedGamepad profiles
  - elements: DPad, A,B,X,Y, L1,R1, LStick,RStick, L2,R2, Select, Start, L3,R3
- Posts `GCControllerDidConnectNotification`.
- On InputState: updates each element's value, calls `valueChangedHandler`.
- On Disconnect: posts `GCControllerDidDisconnectNotification`.

**GCController subclass:**
Reuses MFiWrapper's approach:
- Custom GCController, GCGamepad, GCExtendedGamepad, GCControllerButtonInput, GCControllerAxisInput, GCControllerDirectionPad.
- `tweakSetValues:` updates value and triggers handlers.

**Mapping:**
- leftStickX/Y → leftThumbstick
- rightStickX/Y → rightThumbstick
- dpadX/Y → dpad
- buttons bitmask → buttonA,B,X,Y, leftShoulder (L1), rightShoulder (R1), select (View), start (Menu), leftThumbstickButton (L3), rightThumbstickButton (R3)
- leftTrigger/rightTrigger → leftTrigger/rightTrigger + L2/R2 digital.

### 3. Communication Protocol

**Transport:** Wi-Fi TCP. Chosen over Bluetooth because iOS blocks HID, and MultipeerConnectivity requires both sides to be apps (daemon can't use it easily). Wi-Fi offers:
- Low latency (<20ms typical LAN)
- Reliable (TCP) or low-latency (UDP) – we use TCP for simplicity, can switch to UDP.
- No pairing needed, Bonjour discovery.

**Packet Format (Binary, little-endian):**

```c
struct RemoteControllerPacket {
  uint32_t magic; // 0x52435044 'RCPD'
  uint32_t version; // 1
  uint64_t timestamp_ms; // milliseconds since epoch, for latency calc
  uint32_t sequence;
  float leftStickX;
  float leftStickY;
  float rightStickX;
  float rightStickY;
  float dpadX;
  float dpadY;
  uint32_t buttons; // bitmask
  float leftTrigger; // 0..1
  float rightTrigger; // 0..1
  uint32_t crc; // optional
} __attribute__((packed));
```

Size ~ 60 bytes.

**Buttons:**
- A=1<<0, B=1<<1, X=1<<2, Y=1<<3, L1=1<<4, R1=1<<5, L2=1<<6, R2=1<<7, Menu=1<<8, View=1<<9, L3=1<<10, R3=1<<11

**Flow:**
1. A discovers B via Bonjour.
2. A connects TCP to B:9944.
3. B daemon accepts, sends Connect to tweaks.
4. A sends InputPacket at 60Hz (or only when changed + heartbeat).
5. B daemon forwards to tweak Unix clients.
6. Tweak updates GCController.
7. Game receives input via standard GCController API.

**Reconnect:**
- A detects disconnect, retries with backoff, re-browses Bonjour.
- B daemon on A disconnect: sends Disconnect to tweaks, waits for new A.

**Latency Measurement:**
- A includes timestamp, B echoes timestamp in ACK or tweak can measure? Simpler: A sends ping packet, B responds pong with same timestamp, A calculates RTT.
- Diagnostic UI shows RTT, packet loss (gap in sequence), send rate.

## Security

- No auth for LAN use (can add token later).
- Daemon runs as mobile, not root, to limit privilege.
- Unix socket permissions 777 for tweak access (tweaks run as mobile in app sandbox? Actually app processes run as mobile, but with sandbox. Using /var/tmp may bypass sandbox? Need to test. Alternative: use CPDistributedMessagingCenter or rocketbootstrap).
- For rootless jailbreaks (Dopamine, Palera1n rootless): paths are /var/jb/...

## Compatibility

- iPhone B must be jailbroken (checkra1n, unc0ver, Dopamine, Palera1n).
- Supports rootful and rootless (via THEOS_PACKAGE_SCHEME).
- iOS 13-17 tested (MFiWrapper supported 7-12, but GCController API similar).
- Game must support MFi / extendedGamepad (Stardew Valley does).

## Test Matrix

| Test | Expected |
|------|----------|
| A discovers B via Bonjour | PASS |
| A connects to B TCP | PASS |
| B daemon receives packet | PASS |
| Tweak connects to daemon Unix socket | PASS |
| Game detects controller (GCController.controllers) | PASS |
| Left Stick | PASS |
| Right Stick | PASS |
| D-pad | PASS |
| A,B,X,Y | PASS |
| L1,R1 | PASS |
| L2,R2 | PASS |
| Menu | PASS |
| View | PASS |
| Reconnect | PASS |
| Disconnect | PASS |
| Game restart | PASS |
| Stardew Valley | PASS |

## Limitations

- Requires jailbreak on iPhone B (public API proven impossible).
- Wi-Fi latency dependent on network.
- No Bluetooth fallback (blocked by iOS).
- Rootless jailbreak path handling needed.
- Some games may check for physical controller vendor; we set vendorName to "Remote Controller" which should be accepted as MFi.

## Future Improvements

- UDP mode for lower latency.
- Encryption.
- Multiple controllers (up to 4).
- Motion support (gyro → right stick).
- Haptics feedback from game to A.

## References

- MFiWrapper: https://github.com/meancoot/MFiWrapper (GPL-3.0)
- ControllersForAll: com.orikad.controllersforall
- nControl: chariz repo
- VirtualGameController: robreuss/VirtualGameController
- Apple GameController docs
- iDownloadBlog nControl article
