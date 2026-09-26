#import <Foundation/Foundation.h>
#import "RemoteControllerProtocol.h"

@interface RemoteControllerClient : NSObject

+ (instancetype)shared;
- (void)start;
- (void)stop;

- (NSArray*)currentControllers;

@end
