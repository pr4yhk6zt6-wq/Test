#!/bin/bash
set -e

echo "=== Remote Controller Build Script ==="
echo "This script attempts to build artifacts where possible"
echo "Requires macOS with Xcode for IPA, and Theos for DEB"
echo ""

# Check for Xcode
if command -v xcodebuild &> /dev/null; then
    echo "[*] Xcode found, building ControllerA.ipa..."
    cd ControllerA
    xcodebuild -project ControllerA.xcodeproj -scheme ControllerA -configuration Release archive -archivePath build/ControllerA.xcarchive || echo "Xcode build failed"
    xcodebuild -exportArchive -archivePath build/ControllerA.xcarchive -exportPath build/ -exportOptionsPlist exportOptions.plist || echo "Export failed"
    cd ..
    ls -lh ControllerA/build/*.ipa 2>/dev/null || echo "IPA not built"
else
    echo "[!] xcodebuild not found, skipping IPA build (requires macOS)"
    echo "    To build IPA on Mac:"
    echo "    cd ControllerA && xcodebuild -project ControllerA.xcodeproj -scheme ControllerA -configuration Release archive -archivePath build/ControllerA.xcarchive"
    echo "    xcodebuild -exportArchive -archivePath build/ControllerA.xcarchive -exportPath build/ -exportOptionsPlist exportOptions.plist"
fi

echo ""

# Check for Theos
if [ -n "$THEOS" ] && [ -d "$THEOS" ]; then
    echo "[*] THEOS found at $THEOS, building ReceiverB.deb..."
    cd ReceiverB
    make package || echo "Theos build failed - check toolchain and SDKs"
    cd ..
    ls -lh ReceiverB/packages/*.deb 2>/dev/null || echo "DEB not built"
else
    echo "[!] THEOS not set or not found, skipping DEB build"
    echo "    To build DEB:"
    echo "    export THEOS=/path/to/theos"
    echo "    cd ReceiverB && make package"
    echo "    For rootless: THEOS_PACKAGE_SCHEME=rootless make package"
fi

echo ""
echo "=== Build Summary ==="
echo "ControllerA: SwiftUI app, buildable with Xcode"
echo "ReceiverB: Tweak+Daemon, buildable with Theos"
echo "See docs/INSTALLATION.md for details"
