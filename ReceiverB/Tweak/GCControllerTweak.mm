#import "GCControllerTweak.h"
#import <objc/runtime.h>

static const char *kHandleKey = "tweakHandle";
static const char *kElementsKey = "tweakElements";

@implementation GCController (RemoteController)

- (uint32_t)tweakHandle {
    NSNumber *num = objc_getAssociatedObject(self, kHandleKey);
    return num ? [num unsignedIntValue] : 0;
}
- (void)setTweakHandle:(uint32_t)handle {
    objc_setAssociatedObject(self, kHandleKey, @(handle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSArray*)tweakElements {
    return objc_getAssociatedObject(self, kElementsKey);
}
- (void)setTweakElements:(NSArray *)elements {
    objc_setAssociatedObject(self, kElementsKey, elements, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)tweakUpdateWithPacket:(RemoteControllerPacket)packet {
    // Map packet to MFi elements
    // Order must match factory creation order
    NSArray *elements = self.tweakElements;
    if (!elements || elements.count < RCElementCount) return;

    // DPad
    GCControllerDirectionPad *dpad = elements[RCElementDPad];
    float dpadValues[2] = {packet.dpadX, packet.dpadY};
    [dpad tweakSetValues:dpadValues];

    // Buttons A,B,X,Y
    [elements[RCElementA] tweakSetValue: (packet.buttons & RCButtonA) ? 1.0f : 0.0f];
    [elements[RCElementB] tweakSetValue: (packet.buttons & RCButtonB) ? 1.0f : 0.0f];
    [elements[RCElementX] tweakSetValue: (packet.buttons & RCButtonX) ? 1.0f : 0.0f];
    [elements[RCElementY] tweakSetValue: (packet.buttons & RCButtonY) ? 1.0f : 0.0f];

    // Shoulders L1,R1
    [elements[RCElementL1] tweakSetValue: (packet.buttons & RCButtonL1) ? 1.0f : 0.0f];
    [elements[RCElementR1] tweakSetValue: (packet.buttons & RCButtonR1) ? 1.0f : 0.0f];

    // Thumbsticks
    float leftValues[2] = {packet.leftStickX, packet.leftStickY};
    [elements[RCElementLeftThumbstick] tweakSetValues:leftValues];
    float rightValues[2] = {packet.rightStickX, packet.rightStickY};
    [elements[RCElementRightThumbstick] tweakSetValues:rightValues];

    // Triggers L2,R2 analog + digital
    [elements[RCElementL2] tweakSetValue: packet.leftTrigger];
    [elements[RCElementR2] tweakSetValue: packet.rightTrigger];

    // View, Menu
    [elements[RCElementView] tweakSetValue: (packet.buttons & RCButtonView) ? 1.0f : 0.0f];
    [elements[RCElementMenu] tweakSetValue: (packet.buttons & RCButtonMenu) ? 1.0f : 0.0f];

    // L3,R3
    [elements[RCElementL3] tweakSetValue: (packet.buttons & RCButtonL3) ? 1.0f : 0.0f];
    [elements[RCElementR3] tweakSetValue: (packet.buttons & RCButtonR3) ? 1.0f : 0.0f];
}

@end

@implementation GCGamepad (RemoteController)

+ (GCGamepad*)gamepadForController:(GCController*)controller {
    GCGamepad *gamepad = [[GCGamepad alloc] init];
    // Use KVC to set private properties if needed, or use associated objects
    // For simplicity, set via private API or direct ivar if available
    // Here we use setValue:forKey: for common properties
    @try {
        gamepad.controller = controller;
        NSArray *elements = controller.tweakElements;
        gamepad.dpad = elements[RCElementDPad];
        gamepad.buttonA = elements[RCElementA];
        gamepad.buttonB = elements[RCElementB];
        gamepad.buttonX = elements[RCElementX];
        gamepad.buttonY = elements[RCElementY];
        gamepad.leftShoulder = elements[RCElementL1];
        gamepad.rightShoulder = elements[RCElementR1];
    } @catch (...) {}
    return gamepad;
}

@end

@implementation GCExtendedGamepad (RemoteController)

+ (GCExtendedGamepad*)gamepadForController:(GCController*)controller {
    GCExtendedGamepad *ext = [[GCExtendedGamepad alloc] init];
    @try {
        ext.controller = controller;
        NSArray *elements = controller.tweakElements;
        ext.dpad = elements[RCElementDPad];
        ext.buttonA = elements[RCElementA];
        ext.buttonB = elements[RCElementB];
        ext.buttonX = elements[RCElementX];
        ext.buttonY = elements[RCElementY];
        ext.leftShoulder = elements[RCElementL1];
        ext.rightShoulder = elements[RCElementR1];
        ext.leftThumbstick = elements[RCElementLeftThumbstick];
        ext.rightThumbstick = elements[RCElementRightThumbstick];
        ext.leftTrigger = elements[RCElementL2];
        ext.rightTrigger = elements[RCElementR2];
        // iOS 14+ has buttonMenu, buttonOptions etc - try to set if available
        if ([ext respondsToSelector:@selector(setButtonMenu:)]) {
            [ext setValue:elements[RCElementMenu] forKey:@"buttonMenu"];
        }
    } @catch (...) {}
    return ext;
}

@end

@implementation GCControllerElement (RemoteController)
- (void)tweakSetValue:(float)value {}
- (uint32_t)tweakSetValues:(const float*)value { return 0; }
@end

@implementation GCControllerButtonInput (RemoteController)

+ (GCControllerButtonInput*)buttonWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog {
    GCControllerButtonInput *btn = [[GCControllerButtonInput alloc] init];
    @try {
        // Try to set collection and analog if properties exist
        if ([btn respondsToSelector:@selector(setCollection:)]) {
            [btn setValue:parent forKey:@"collection"];
        }
    } @catch (...) {}
    return btn;
}

- (void)tweakSetValue:(float)value {
    @try {
        if (self.value != value) {
            self.value = value;
            self.pressed = value > 0.1f;
            if (self.valueChangedHandler) {
                self.valueChangedHandler(self, value, self.pressed);
            }
        }
    } @catch (...) {
        // Fallback via KVC
        @try {
            [self setValue:@(value) forKey:@"value"];
            [self setValue:@(value > 0.1f) forKey:@"pressed"];
        } @catch (...) {}
    }
}

- (uint32_t)tweakSetValues:(const float*)values {
    [self tweakSetValue:values[0]];
    return 1;
}

@end

@implementation GCControllerAxisInput (RemoteController)

+ (GCControllerAxisInput*)axisWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog {
    GCControllerAxisInput *axis = [[GCControllerAxisInput alloc] init];
    return axis;
}

- (void)tweakSetValue:(float)value {
    @try {
        if (self.value != value) {
            self.value = value;
            if (self.valueChangedHandler) {
                self.valueChangedHandler(self, value);
            }
        }
    } @catch (...) {}
}

- (uint32_t)tweakSetValues:(const float*)values {
    [self tweakSetValue:values[0]];
    return 1;
}

@end

@implementation GCControllerDirectionPad (RemoteController)

+ (GCControllerDirectionPad*)dpadWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog {
    GCControllerDirectionPad *dpad = [[GCControllerDirectionPad alloc] init];
    @try {
        GCControllerAxisInput *xAxis = [GCControllerAxisInput axisWithParent:dpad analog:isAnalog];
        GCControllerAxisInput *yAxis = [GCControllerAxisInput axisWithParent:dpad analog:isAnalog];
        GCControllerButtonInput *up = [GCControllerButtonInput buttonWithParent:dpad analog:isAnalog];
        GCControllerButtonInput *down = [GCControllerButtonInput buttonWithParent:dpad analog:isAnalog];
        GCControllerButtonInput *left = [GCControllerButtonInput buttonWithParent:dpad analog:isAnalog];
        GCControllerButtonInput *right = [GCControllerButtonInput buttonWithParent:dpad analog:isAnalog];
        dpad.xAxis = xAxis;
        dpad.yAxis = yAxis;
        dpad.up = up;
        dpad.down = down;
        dpad.left = left;
        dpad.right = right;
    } @catch (...) {}
    return dpad;
}

- (uint32_t)tweakSetValues:(const float*)values {
    @try {
        float x = values[0];
        float y = values[1];
        if (self.xAxis.value == x && self.yAxis.value == y) return 2;
        [self.xAxis tweakSetValue:x];
        [self.yAxis tweakSetValue:y];
        [self.left tweakSetValue: (x < 0) ? fabsf(x) : 0];
        [self.right tweakSetValue: (x > 0) ? x : 0];
        [self.up tweakSetValue: (y > 0) ? y : 0];
        [self.down tweakSetValue: (y < 0) ? fabsf(y) : 0];
        if (self.valueChangedHandler) {
            self.valueChangedHandler(self, x, y);
        }
    } @catch (...) {}
    return 2;
}

@end

@implementation RemoteGCControllerFactory

+ (GCController*)controllerForHandle:(uint32_t)handle vendorName:(NSString*)name {
    GCController *controller = [[GCController alloc] init];
    controller.tweakHandle = handle;
    @try {
        [controller setValue:name forKey:@"vendorName"];
    } @catch (...) {}

    // Create elements in order of RCElementIndex
    NSMutableArray *elements = [NSMutableArray array];
    // DPad
    [elements addObject:[GCControllerDirectionPad dpadWithParent:nil analog:YES]]; // 0
    // A,B,X,Y
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // A
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // B
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // X
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // Y
    // L1,R1
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // L1
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // R1
    // Left Thumbstick
    [elements addObject:[GCControllerDirectionPad dpadWithParent:nil analog:YES]]; // LeftThumb
    // Right Thumbstick
    [elements addObject:[GCControllerDirectionPad dpadWithParent:nil analog:YES]]; // RightThumb
    // L2,R2
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:YES]]; // L2
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:YES]]; // R2
    // View, Menu
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // View
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // Menu
    // L3,R3
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // L3
    [elements addObject:[GCControllerButtonInput buttonWithParent:nil analog:NO]]; // R3

    controller.tweakElements = elements;

    @try {
        GCGamepad *gamepad = [GCGamepad gamepadForController:controller];
        [controller setValue:gamepad forKey:@"gamepad"];
        GCExtendedGamepad *ext = [GCExtendedGamepad gamepadForController:controller];
        [controller setValue:ext forKey:@"extendedGamepad"];
        [controller setValue:@(0) forKey:@"playerIndex"];
    } @catch (...) {
        NSLog(@"[RemoteController] Failed to set gamepad properties");
    }

    return controller;
}

@end
