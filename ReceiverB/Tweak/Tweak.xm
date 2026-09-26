#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import "RemoteControllerClient.h"
#import "GCControllerTweak.h"

%hook NSNotificationCenter

- (id)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *))block {
    id result = %orig;
    if ([name isEqualToString:@"GCControllerDidConnectNotification"]) {
        // Trigger initial fetch
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *controllers = [[RemoteControllerClient shared] currentControllers];
            for (GCController *c in controllers) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"GCControllerDidConnectNotification" object:c];
            }
        });
    }
    return result;
}

- (void)addObserver:(id)observer selector:(SEL)sel name:(NSString *)name object:(id)object {
    %orig;
    if ([name isEqualToString:@"GCControllerDidConnectNotification"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *controllers = [[RemoteControllerClient shared] currentControllers];
            for (GCController *c in controllers) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"GCControllerDidConnectNotification" object:c];
            }
        });
    }
}

%end

%hook GCController

+ (NSArray *)controllers {
    NSArray *realControllers = %orig;
    NSArray *remoteControllers = [[RemoteControllerClient shared] currentControllers];
    if (remoteControllers.count == 0) return realControllers;
    NSMutableArray *merged = [NSMutableArray arrayWithArray:realControllers];
    for (GCController *rc in remoteControllers) {
        if (![merged containsObject:rc]) {
            [merged addObject:rc];
        }
    }
    return merged;
}

+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))completionHandler {
    %orig;
    // Also trigger remote discovery
    if (completionHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    }
}

+ (void)stopWirelessControllerDiscovery {
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSLog(@"[RemoteController] Tweak loaded into %@", [[NSBundle mainBundle] bundleIdentifier]);
        [[RemoteControllerClient shared] start];
    }
}
