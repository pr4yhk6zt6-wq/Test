ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:13.0

TOOL_NAME = remotecontrollerd
remotecontrollerd_FILES = main.m RemoteControllerDaemon.m
remotecontrollerd_FRAMEWORKS = Foundation
remotecontrollerd_CFLAGS = -fobjc-arc -I.
remotecontrollerd_INSTALL_PATH = /usr/bin

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk
