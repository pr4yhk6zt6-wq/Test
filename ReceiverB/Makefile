THEOS_DEVICE_IP = 127.0.0.1
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = SpringBoard

TWEAK_NAME = RemoteController
RemoteController_FILES = Tweak/Tweak.xm Tweak/GCControllerTweak.mm Tweak/RemoteControllerClient.mm
RemoteController_CFLAGS = -fobjc-arc -I Tweak -I Daemon
RemoteController_LDFLAGS = -lsubstrate
RemoteController_FRAMEWORKS = GameController Foundation UIKit

TOOL_NAME = remotecontrollerd
remotecontrollerd_FILES = Daemon/main.m Daemon/RemoteControllerDaemon.m
remotecontrollerd_FRAMEWORKS = Foundation
remotecontrollerd_CFLAGS = -fobjc-arc -I Daemon
remotecontrollerd_INSTALL_PATH = /usr/bin

BUNDLE_NAME = RemoteControllerSettings
RemoteControllerSettings_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)cp LaunchDaemon/com.example.remotecontrollerd.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/$(ECHO_END)

after-install::
	install.exec "launchctl unload /Library/LaunchDaemons/com.example.remotecontrollerd.plist; launchctl load /Library/LaunchDaemons/com.example.remotecontrollerd.plist"
