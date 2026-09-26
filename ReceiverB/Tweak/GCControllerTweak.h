#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import "RemoteControllerProtocol.h"

@interface GCController (RemoteController)
@property (nonatomic, assign) uint32_t tweakHandle;
@property (nonatomic, retain) NSArray *tweakElements;
- (void)tweakUpdateWithPacket:(RemoteControllerPacket)packet;
@end

@interface GCGamepad (RemoteController)
+ (GCGamepad*)gamepadForController:(GCController*)controller;
@end

@interface GCExtendedGamepad (RemoteController)
+ (GCExtendedGamepad*)gamepadForController:(GCController*)controller;
@end

@interface GCControllerElement (RemoteController)
- (void)tweakSetValue:(float)value;
- (uint32_t)tweakSetValues:(const float*)value;
@end

@interface GCControllerButtonInput (RemoteController)
+ (GCControllerButtonInput*)buttonWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog;
@end

@interface GCControllerAxisInput (RemoteController)
+ (GCControllerAxisInput*)axisWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog;
@end

@interface GCControllerDirectionPad (RemoteController)
+ (GCControllerDirectionPad*)dpadWithParent:(GCControllerElement*)parent analog:(BOOL)isAnalog;
@end

// Factory
@interface RemoteGCControllerFactory : NSObject
+ (GCController*)controllerForHandle:(uint32_t)handle vendorName:(NSString*)name;
@end
