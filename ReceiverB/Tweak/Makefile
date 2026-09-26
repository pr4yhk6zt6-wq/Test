THEOS_DEVICE_IP = 127.0.0.1
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = SpringBoard

TWEAK_NAME = RemoteController

RemoteController_FILES = Tweak.xm GCControllerTweak.mm RemoteControllerClient.mm
RemoteController_CFLAGS = -fobjc-arc -I../Daemon
RemoteController_LDFLAGS = -lsubstrate
RemoteController_FRAMEWORKS = GameController Foundation UIKit

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
