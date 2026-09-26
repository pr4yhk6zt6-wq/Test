# Installation Guide

## Device Requirements

- **iPhone A**: Any iPhone, iOS 15+, no jailbreak needed. Will be controller.
- **iPhone B**: Jailbroken iPhone, iOS 13-17 recommended.
  - Jailbreak types: checkra1n, unc0ver, Dopamine (rootless), Palera1n (rootful/rootless)
  - Must support MobileSubstrate / Substitute / ElleKit
  - Must allow launch daemons
- Both on same Wi-Fi network
- Native game supporting MFi controller (Stardew Valley tested conceptually)

## ControllerA (iPhone A)

### Build from source (requires Mac)

1. Clone repo
2. Open `ControllerA/ControllerA.xcodeproj` in Xcode 14+
3. Select your team, bundle ID `com.example.remotecontrollerA` (change if needed)
4. Connect iPhone A, select as run destination
5. Product → Run (Cmd+R)
6. On first launch, allow Local Network permission

### IPA (if prebuilt)

If you have `ControllerA.ipa`:
1. Install via AltStore, Sideloadly, or TrollStore
2. Trust developer profile in Settings → General → VPN & Device Management
3. Ensure Local Network permission granted

### Usage

1. Open app, you should see controller UI
2. Tap Wi-Fi icon top-right to open connection sheet
3. If iPhone B daemon is running and on same Wi-Fi, it should appear under Discovered Devices (Bonjour _remotegamepad._tcp)
4. Tap to connect, or enter IP manually (e.g., 192.168.1.10)
5. Status should show "Connected"
6. Controller input now sends at 60Hz

## ReceiverB (iPhone B)

### Prerequisites

- Jailbroken
- Theos installed (if building from source)
- Filza or terminal with dpkg

### Option 1: Install prebuilt .deb (if available)

1. Copy `com.example.remotecontroller_1.0.0_iphoneos-arm.deb` to device
2. Install via Filza: tap deb → Install, or via terminal: `dpkg -i com.example.remotecontroller_*.deb`
3. Respring: `killall SpringBoard` or via tweak manager
4. Check daemon: `ps aux | grep remotecontrollerd` should show process
5. Check log: `cat /var/mobile/Library/Logs/remotecontrollerd.log`
6. Check Bonjour: on Mac, `dns-sd -B _remotegamepad._tcp` should show device

### Option 2: Build from source

On macOS or Linux with Theos:

```bash
# Install Theos per https://theos.github.io/docs/Installation.html
# Ensure sdks in $THEOS/sdks (iPhoneOS14.5.sdk or newer)
# Ensure toolchain installed

cd ReceiverB
make package
# Output: packages/com.example.remotecontroller_1.0.0_iphoneos-arm.deb

# Copy to device and install
scp packages/*.deb mobile@<iphone-b-ip>:~/
ssh mobile@<iphone-b-ip> "dpkg -i com.example.remotecontroller_*.deb"
ssh mobile@<iphone-b-ip> "launchctl unload /Library/LaunchDaemons/com.example.remotecontrollerd.plist; launchctl load /Library/LaunchDaemons/com.example.remotecontrollerd.plist; killall SpringBoard"
```

For rootless (Dopamine):
```bash
THEOS_PACKAGE_SCHEME=rootless make package
```

### Verify Installation

1. **Daemon running**: `ps aux | grep remotecontrollerd` or `launchctl list | grep remotecontroller`
2. **Unix socket exists**: `ls -lh /var/tmp/remote_controller.sock` or `/var/jb/var/tmp/remote_controller.sock` (rootless)
3. **TCP listening**: `netstat -an | grep 9944` or `lsof -i :9944`
4. **Bonjour advertising**: Check logs or use Bonjour browser app
5. **Tweak loaded**: Install any app that logs GCController, e.g., create test app:
   ```swift
   import GameController
   print(GCController.controllers())
   NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: nil) { note in
     print("Controller connected: \(note.object)")
   }
   ```
   Or check via console: `oslog` or `socat`

### LaunchDaemon troubleshooting

If daemon not starting:
- Check plist: `cat /Library/LaunchDaemons/com.example.remotecontrollerd.plist`
- Check permissions: `ls -l /usr/bin/remotecontrollerd` should be 0755
- Manual run: `/usr/bin/remotecontrollerd` (as mobile) and watch logs
- Rootless path: `/var/jb/usr/bin/remotecontrollerd` and plist in `/var/jb/Library/LaunchDaemons/`

## Game Setup (Stardew Valley)

1. Ensure ReceiverB installed and daemon running on iPhone B
2. Connect iPhone A to iPhone B via ControllerA app
3. Open Stardew Valley on iPhone B
4. Game should detect controller automatically (check in-game settings → Controls)
5. If not detected, check:
   - Is tweak loaded? Try respring
   - Is daemon connected? Check ControllerA shows Connected
   - Try killing and reopening game
   - Check logs: `cat /var/mobile/Library/Logs/remotecontrollerd.log`

## Uninstall

- Remove deb: `dpkg -r com.example.remotecontroller`
- Or via package manager (Sileo/Zebra)
- Respring

## Signing

- ControllerA: standard iOS signing via Xcode, no special entitlements except Local Network
- ReceiverB: jailbreak, no signing needed (installed via dpkg). If building for TrollStore, sign with ldid.
