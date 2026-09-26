#import "RemoteControllerClient.h"
#import "GCControllerTweak.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

@interface RemoteControllerClient ()
@property (nonatomic, strong) NSMutableArray *controllers;
@property (nonatomic, assign) int unixSocket;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation RemoteControllerClient

+ (instancetype)shared {
    static RemoteControllerClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RemoteControllerClient alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _controllers = [NSMutableArray array];
        _queue = dispatch_queue_create("com.example.remotecontroller.client", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    if (_running) return;
    _running = YES;
    dispatch_async(_queue, ^{
        [self connectLoop];
    });
}

- (void)stop {
    _running = NO;
    if (_unixSocket > 0) {
        close(_unixSocket);
        _unixSocket = 0;
    }
}

- (void)connectLoop {
    while (_running) {
        const char *paths[] = {RC_UNIX_SOCKET_PATH, RC_UNIX_SOCKET_PATH_ROOTLESS, NULL};
        int sock = -1;
        for (int i=0; paths[i]; i++) {
            sock = socket(AF_UNIX, SOCK_STREAM, 0);
            if (sock < 0) continue;
            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, paths[i], sizeof(addr.sun_path)-1);
            if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
                NSLog(@"[RemoteControllerClient] Connected to daemon at %s", paths[i]);
                break;
            }
            close(sock);
            sock = -1;
        }
        if (sock < 0) {
            NSLog(@"[RemoteControllerClient] Failed to connect to daemon, retrying in 2s");
            sleep(2);
            continue;
        }
        self.unixSocket = sock;
        [self receiveLoop:sock];
        close(sock);
        self.unixSocket = 0;
        NSLog(@"[RemoteControllerClient] Disconnected from daemon, reconnecting...");
        sleep(1);
    }
}

- (void)receiveLoop:(int)sock {
    uint8_t buffer[8192];
    NSMutableData *accum = [NSMutableData data];
    while (_running) {
        ssize_t n = recv(sock, buffer, sizeof(buffer), 0);
        if (n <= 0) break;
        [accum appendBytes:buffer length:n];
        while (accum.length >= sizeof(RCInternalPacket)) {
            RCInternalPacket pkt;
            [accum getBytes:&pkt length:sizeof(pkt)];
            if (pkt.size != sizeof(pkt) || pkt.size > accum.length) {
                // Wait for more data if size mismatch
                if (pkt.size > sizeof(pkt) && accum.length < pkt.size) break;
                // Invalid, skip
                [accum replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                continue;
            }
            [accum replaceBytesInRange:NSMakeRange(0, sizeof(pkt)) withBytes:NULL length:0];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handlePacket:pkt];
            });
        }
    }
}

- (void)handlePacket:(RCInternalPacket)pkt {
    switch (pkt.type) {
        case RCPacketTypeConnect:
            [self handleConnect:pkt];
            break;
        case RCPacketTypeDisconnect:
            [self handleDisconnect:pkt];
            break;
        case RCPacketTypeInputState:
            [self handleInput:pkt];
            break;
        default:
            break;
    }
}

- (void)handleConnect:(RCInternalPacket)pkt {
    NSLog(@"[RemoteControllerClient] Received Connect handle %u", pkt.handle);
    // Check if already exists
    for (GCController *c in _controllers) {
        if (c.tweakHandle == pkt.handle) return;
    }
    NSString *vendor = [NSString stringWithUTF8String:pkt.connect.vendorName];
    if (vendor.length == 0) vendor = @"Remote Controller";
    GCController *controller = [RemoteGCControllerFactory controllerForHandle:pkt.handle vendorName:vendor];
    [_controllers addObject:controller];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GCControllerDidConnectNotification" object:controller];
    NSLog(@"[RemoteControllerClient] Posted connect notification");
}

- (void)handleDisconnect:(RCInternalPacket)pkt {
    NSLog(@"[RemoteControllerClient] Received Disconnect handle %u", pkt.handle);
    GCController *toRemove = nil;
    for (GCController *c in _controllers) {
        if (c.tweakHandle == pkt.handle) {
            toRemove = c;
            break;
        }
    }
    if (toRemove) {
        [_controllers removeObject:toRemove];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"GCControllerDidDisconnectNotification" object:toRemove];
    }
}

- (void)handleInput:(RCInternalPacket)pkt {
    for (GCController *c in _controllers) {
        if (c.tweakHandle == pkt.handle) {
            [c tweakUpdateWithPacket:pkt.input];
            break;
        }
    }
}

- (NSArray*)currentControllers {
    return [_controllers copy];
}

@end
