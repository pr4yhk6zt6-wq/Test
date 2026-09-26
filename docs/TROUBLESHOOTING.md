# Troubleshooting

## ControllerA (iPhone A)

### No devices discovered

- Ensure iPhone B and A on same Wi-Fi (same subnet)
- Check iPhone B daemon running: `ps aux | grep remotecontrollerd`
- Check Bonjour: On Mac, `dns-sd -B _remotegamepad._tcp` or use Discovery app
- Check firewall: iOS shouldn't block, but router might block multicast
- Try manual IP: enter iPhone B IP (Settings → Wi-Fi → tap network → IP Address)
- Ensure Local Network permission granted: Settings → Privacy → Local Network → ControllerA ON

### Cannot connect via manual IP

- Check IP correct, port 9944 open: `nc -zv <ip> 9944` from Mac
- Check daemon listening: on B, `netstat -an | grep 9944` or `lsof -i :9944`
- Check daemon log: `cat /var/mobile/Library/Logs/remotecontrollerd.log`
- Try restart daemon: `launchctl unload /Library/LaunchDaemons/com.example.remotecontrollerd.plist; launchctl load /Library/LaunchDaemons/com.example.remotecontrollerd.plist`
- Check if rootless: path may be /var/jb/... Use `THEOS_PACKAGE_SCHEME=rootless` build

### Connected but no input in game

- This is expected if ReceiverB not installed or tweak not loaded
- Check B side: daemon log should show "Controller connected" and "New TCP client"
- Check Unix socket: `ls -lh /var/tmp/remote_controller.sock`
- Check tweak loaded: need respring after install
- Check game supports MFi: Stardew Valley does, but some games only support specific controllers

### High latency or packet loss

- Use 5GHz Wi-Fi, close to router
- Reduce interference, ensure strong signal
- Diagnostic overlay shows RTT - should be <50ms on LAN
- If >100ms, check network congestion
- Future: switch to UDP mode

## ReceiverB (iPhone B)

### Daemon not running

- Check plist exists: `ls /Library/LaunchDaemons/com.example.remotecontrollerd.plist` (or /var/jb/...)
- Check binary exists: `ls -lh /usr/bin/remotecontrollerd`
- Check permissions: `chmod 0755 /usr/bin/remotecontrollerd`
- Manual run: `/usr/bin/remotecontrollerd` as mobile user, watch output
- Check log file directory exists: `mkdir -p /var/mobile/Library/Logs`
- For rootless: binary at /var/jb/usr/bin/remotecontrollerd, plist at /var/jb/Library/LaunchDaemons/

### Unix socket permission denied

- Tweak runs inside app sandbox as mobile, needs world-writable socket
- Our daemon chmod 0777 socket, but check: `ls -lh /var/tmp/remote_controller.sock` should show srwxrwxrwx
- If sandbox still blocks, we may need to use rocketbootstrap or CPDistributedMessagingCenter
- Alternative: use /var/mobile/Library/RemoteController/socket with mobile:mobile ownership

### Tweak not loaded

- Check installed: `dpkg -l | grep remotecontroller`
- Check dylib exists: `ls /Library/MobileSubstrate/DynamicLibraries/RemoteController.dylib` (or /var/jb/...)
- Check plist filter: should be `Bundles = ("com.apple.GameController")`
- Respring: `killall SpringBoard` or `sbreload`
- Check logs: `oslog` or use `socat` to view syslog, or install Cr4shed
- Ensure MobileSubstrate/Substitute/ElleKit installed and working
- Try loading in specific app: add Executables filter for game bundle ID

### Game doesn't detect controller

- Check GCController.controllers() in a test app - does it include "Remote Controller"?
- If not, tweak not loaded or daemon not connected
- Check ControllerA shows Connected and daemon log shows input forwarding
- Some games check for controller at launch only - kill and reopen game after connecting
- Check game supports extendedGamepad - Stardew Valley does
- Try other MFi games to isolate

### Stardew Valley specific

- Stardew Valley supports MFi controllers, but may need to enable in settings
- Check in-game: Options → Controls → Controller - should show connected
- If not, try: close game, connect controller, reopen game
- Ensure no other physical controller connected that might take playerIndex 1
- Our tweak sets playerIndex to 0 (unset), game should assign

### Rootless vs Rootful

- Rootful: files in /Library/..., /usr/bin/...
- Rootless (Dopamine, Palera1n rootless): files in /var/jb/Library/..., /var/jb/usr/bin/...
- Build with `THEOS_PACKAGE_SCHEME=rootless make package` for rootless
- Our code tries both socket paths, but plist and binary must match jailbreak type

### Build issues (Theos)

- Error: `make package requires dm.pl` - need fakeroot, dpkg, perl
- Error: `clang: No such file` - need toolchain, download from sbingner releases
- Error: `SDK not found` - need sdks in $THEOS/sdks, clone from theos/sdks
- On Linux, install dependencies: build-essential, dpkg, fakeroot, perl, etc.

### Signing issues (ControllerA)

- Ensure bundle ID unique, team selected
- Local Network entitlement requires NSLocalNetworkUsageDescription in Info.plist (we have)
- Bonjour requires NSBonjourServices (we have _remotegamepad._tcp)
- If building for device, need Apple Developer account (free works)

## Common Failures Matrix

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| No Bonjour devices | Daemon not running / different Wi-Fi | Check daemon, same Wi-Fi |
| TCP connect fails | Firewall / wrong IP / daemon not listening | Check netstat, manual IP, logs |
| Connected but game no controller | Tweak not loaded / socket perm | Respring, check socket 0777, check logs |
| Controller connects then disconnects immediately | Daemon crash / packet parse fail | Check daemon log, update app |
| Input laggy | Wi-Fi congestion / 2.4GHz | Use 5GHz, close to router |
| Only some buttons work | Mapping mismatch | Check packet mapping, update tweak |
| Game sees controller but no input | valueChangedHandler not triggered | Check GCControllerTweak implementation |
| Works in one game but not another | Game uses private API or checks vendor | Try setting vendor to "SteelSeries Nimbus" or similar |

## Debug Mode

Enable verbose logging:

- Daemon: logs to /var/mobile/Library/Logs/remotecontrollerd.log and NSLog (visible via `oslog` or Console app)
- Tweak: NSLog to syslog, view via `oslog` or `idevicesyslog` or `socat`
- ControllerA: Xcode console or on-device via Console app

Diagnostic overlay in ControllerA shows RTT, loss, rate.

## Getting Help

- Check docs/ARCHITECTURE.md for design
- Check GitHub issues for MFiWrapper for similar problems
- For jailbreak issues, check r/jailbreak, Theos docs
- For GameController issues, check Apple docs, WWDC videos
