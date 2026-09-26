ControllerA IPA Build

This directory should contain ControllerA.ipa after building on macOS with Xcode.

To build:

1. Open ControllerA.xcodeproj in Xcode 14+
2. Select your team
3. Product -> Archive
4. Distribute App -> Development -> Export

Or via command line:

xcodebuild -project ControllerA.xcodeproj -scheme ControllerA -configuration Release archive -archivePath build/ControllerA.xcarchive
xcodebuild -exportArchive -archivePath build/ControllerA.xcarchive -exportPath build/ -exportOptionsPlist exportOptions.plist

Result: build/ControllerA.ipa

This IPA cannot be built in Linux sandbox without Xcode. Use GitHub Actions workflow .github/workflows/build.yml which runs on macos-14 runner and builds IPA.

For testing without iOS device, use Simulator/ which proves protocol works on Linux/macOS.

See docs/INSTALLATION.md
