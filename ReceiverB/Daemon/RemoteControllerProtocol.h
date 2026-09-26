#pragma once
#include <stdint.h>

#define RC_MAGIC 0x52435044 // 'RCPD'
#define RC_VERSION 1
#define RC_PORT 9944
#define RC_BONJOUR_TYPE "_remotegamepad._tcp"
#define RC_UNIX_SOCKET_PATH "/var/tmp/remote_controller.sock"
#define RC_UNIX_SOCKET_PATH_ROOTLESS "/var/jb/var/tmp/remote_controller.sock"

// Buttons bitmask - matches requirements
typedef enum {
    RCButtonA = 1 << 0,
    RCButtonB = 1 << 1,
    RCButtonX = 1 << 2,
    RCButtonY = 1 << 3,
    RCButtonL1 = 1 << 4,
    RCButtonR1 = 1 << 5,
    RCButtonL2 = 1 << 6, // digital L2
    RCButtonR2 = 1 << 7, // digital R2
    RCButtonMenu = 1 << 8, // Start/Menu
    RCButtonView = 1 << 9, // Select/View
    RCButtonL3 = 1 << 10,
    RCButtonR3 = 1 << 11,
} RCButtons;

#pragma pack(push, 1)
typedef struct {
    uint32_t magic; // RC_MAGIC
    uint32_t version;
    uint64_t timestamp_ms;
    uint32_t sequence;
    float leftStickX;   // -1..1
    float leftStickY;   // -1..1
    float rightStickX;  // -1..1
    float rightStickY;  // -1..1
    float dpadX;        // -1..1
    float dpadY;        // -1..1
    uint32_t buttons;   // RCButtons bitmask
    float leftTrigger;  // 0..1
    float rightTrigger; // 0..1
    // padding for future
    uint32_t reserved;
} RemoteControllerPacket;

typedef enum {
    RCPacketTypeConnect = 1,
    RCPacketTypeDisconnect = 2,
    RCPacketTypeInputState = 3,
    RCPacketTypePing = 4,
    RCPacketTypePong = 5,
} RCPacketType;

// Internal packet used between daemon and tweak (similar to MFiWrapper)
typedef struct {
    uint32_t size; // total size including header
    uint32_t type; // RCPacketType
    uint32_t handle; // controller handle, 1 for single controller
    union {
        struct {
            char vendorName[64];
            uint32_t presentControls;
            uint32_t analogControls;
        } connect;
        RemoteControllerPacket input;
        struct {
            uint64_t timestamp_ms;
            uint32_t sequence;
        } ping;
    };
} RCInternalPacket;

#pragma pack(pop)

#define RC_INTERNAL_CONNECT_SIZE (sizeof(uint32_t)*3 + 64 + 4 + 4)
#define RC_INTERNAL_INPUT_SIZE (sizeof(uint32_t)*3 + sizeof(RemoteControllerPacket))
#define RC_INTERNAL_PING_SIZE (sizeof(uint32_t)*3 + sizeof(uint64_t) + sizeof(uint32_t))

// MFi-style element indices for tweak
typedef enum {
    RCElementDPad = 0,
    RCElementA,
    RCElementB,
    RCElementX,
    RCElementY,
    RCElementL1,
    RCElementR1,
    RCElementLeftThumbstick,
    RCElementRightThumbstick,
    RCElementL2,
    RCElementR2,
    RCElementView,
    RCElementMenu,
    RCElementL3,
    RCElementR3,
    RCElementCount
} RCElementIndex;
