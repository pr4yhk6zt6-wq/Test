#import <Foundation/Foundation.h>

@interface RemoteControllerDaemon : NSObject <NSNetServiceDelegate>

- (void)start;
- (void)stop;

@end
