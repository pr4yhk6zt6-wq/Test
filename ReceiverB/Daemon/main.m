#import <Foundation/Foundation.h>
#import "RemoteControllerDaemon.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"[RemoteControllerDaemon] Starting...");
        RemoteControllerDaemon *daemon = [[RemoteControllerDaemon alloc] init];
        [daemon start];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
