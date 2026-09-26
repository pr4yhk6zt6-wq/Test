#import "RemoteControllerDaemon.h"
#import "RemoteControllerProtocol.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/un.h>

@interface RemoteControllerDaemon ()
@property (nonatomic, strong) NSNetService *bonjourService;
@property (nonatomic, assign) int tcpServerSocket;
@property (nonatomic, assign) int unixServerSocket;
@property (nonatomic, strong) NSMutableArray *tcpClients; // array of NSValue with int socket
@property (nonatomic, strong) NSMutableArray *unixClients;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) uint32_t controllerHandle;
@property (nonatomic, assign) BOOL hasController;
@property (nonatomic, strong) NSMutableData *recvBuffer;
@end

@implementation RemoteControllerDaemon

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.example.remotecontrollerd", DISPATCH_QUEUE_CONCURRENT);
        _tcpClients = [NSMutableArray array];
        _unixClients = [NSMutableArray array];
        _controllerHandle = 1;
        _hasController = NO;
        _recvBuffer = [NSMutableData data];
    }
    return self;
}

- (void)start {
    [self startTCPServer];
    [self startUnixServer];
    [self startBonjour];
    NSLog(@"[RemoteControllerDaemon] Daemon started on port %d, unix socket %s", RC_PORT, RC_UNIX_SOCKET_PATH);
}

- (void)stop {
    if (_tcpServerSocket > 0) {
        close(_tcpServerSocket);
    }
    if (_unixServerSocket > 0) {
        close(_unixServerSocket);
        unlink(RC_UNIX_SOCKET_PATH);
        unlink(RC_UNIX_SOCKET_PATH_ROOTLESS);
    }
    [_bonjourService stop];
}

- (void)startBonjour {
    self.bonjourService = [[NSNetService alloc] initWithDomain:@"local." type:@RC_BONJOUR_TYPE name:@"" port:RC_PORT];
    self.bonjourService.delegate = self;
    [self.bonjourService publish];
    NSLog(@"[RemoteControllerDaemon] Bonjour service publishing: %s", RC_BONJOUR_TYPE);
}

- (void)startTCPServer {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        NSLog(@"[RemoteControllerDaemon] Failed to create TCP socket");
        return;
    }
    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(RC_PORT);
    if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        NSLog(@"[RemoteControllerDaemon] Failed to bind TCP socket: %s", strerror(errno));
        close(sock);
        return;
    }
    if (listen(sock, 5) < 0) {
        NSLog(@"[RemoteControllerDaemon] Failed to listen TCP");
        close(sock);
        return;
    }
    self.tcpServerSocket = sock;
    dispatch_async(_queue, ^{
        [self acceptTCPLoop];
    });
}

- (void)acceptTCPLoop {
    while (1) {
        struct sockaddr_in clientAddr;
        socklen_t len = sizeof(clientAddr);
        int clientSock = accept(self.tcpServerSocket, (struct sockaddr*)&clientAddr, &len);
        if (clientSock < 0) {
            NSLog(@"[RemoteControllerDaemon] Accept failed: %s", strerror(errno));
            sleep(1);
            continue;
        }
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &clientAddr.sin_addr, ip, sizeof(ip));
        NSLog(@"[RemoteControllerDaemon] New TCP client from %s:%d", ip, ntohs(clientAddr.sin_port));
        @synchronized (self.tcpClients) {
            [self.tcpClients addObject:@(clientSock)];
        }
        dispatch_async(self.queue, ^{
            [self handleTCPClient:clientSock];
        });
    }
}

- (void)handleTCPClient:(int)clientSock {
    NSMutableData *buffer = [NSMutableData data];
    uint8_t temp[4096];
    while (1) {
        ssize_t n = recv(clientSock, temp, sizeof(temp), 0);
        if (n <= 0) {
            NSLog(@"[RemoteControllerDaemon] TCP client disconnected: %d", clientSock);
            break;
        }
        [buffer appendBytes:temp length:n];
        // Process packets: 4-byte len + packet
        while (buffer.length >= 4) {
            uint32_t pktLen = 0;
            [buffer getBytes:&pktLen length:4];
            pktLen = CFSwapInt32LittleToHost(pktLen);
            if (buffer.length < 4 + pktLen) break;
            NSData *pktData = [buffer subdataWithRange:NSMakeRange(4, pktLen)];
            [buffer replaceBytesInRange:NSMakeRange(0, 4+pktLen) withBytes:NULL length:0];
            [self processRemotePacket:pktData fromSocket:clientSock];
        }
    }
    close(clientSock);
    @synchronized (self.tcpClients) {
        [self.tcpClients removeObject:@(clientSock)];
    }
    // If this was the controller, send disconnect to tweaks
    if (self.hasController) {
        self.hasController = NO;
        [self sendDisconnectToTweaks];
    }
}

- (void)processRemotePacket:(NSData*)data fromSocket:(int)sock {
    if (data.length < sizeof(RemoteControllerPacket)) {
        NSLog(@"[RemoteControllerDaemon] Packet too small: %lu", (unsigned long)data.length);
        return;
    }
    RemoteControllerPacket pkt;
    [data getBytes:&pkt length:sizeof(pkt)];
    if (pkt.magic != RC_MAGIC) {
        NSLog(@"[RemoteControllerDaemon] Invalid magic: %x", pkt.magic);
        return;
    }
    // First packet = connect
    if (!self.hasController) {
        self.hasController = YES;
        [self sendConnectToTweaks];
        NSLog(@"[RemoteControllerDaemon] Controller connected, sending Connect to tweaks");
    }
    // Forward to tweaks
    [self sendInputToTweaks:pkt];
}

- (void)startUnixServer {
    // Try both paths for rootless/rootful
    const char *paths[] = {RC_UNIX_SOCKET_PATH, RC_UNIX_SOCKET_PATH_ROOTLESS, NULL};
    int sock = -1;
    const char *chosenPath = NULL;
    for (int i=0; paths[i]; i++) {
        unlink(paths[i]);
        sock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sock < 0) continue;
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, paths[i], sizeof(addr.sun_path)-1);
        // Ensure directory exists
        NSString *dir = [@(paths[i]) stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            chmod(paths[i], 0777);
            chosenPath = paths[i];
            break;
        }
        close(sock);
        sock = -1;
    }
    if (sock < 0) {
        NSLog(@"[RemoteControllerDaemon] Failed to create Unix socket");
        return;
    }
    listen(sock, 10);
    self.unixServerSocket = sock;
    NSLog(@"[RemoteControllerDaemon] Unix socket listening at %s", chosenPath);
    dispatch_async(_queue, ^{
        [self acceptUnixLoop];
    });
}

- (void)acceptUnixLoop {
    while (1) {
        struct sockaddr_un clientAddr;
        socklen_t len = sizeof(clientAddr);
        int clientSock = accept(self.unixServerSocket, (struct sockaddr*)&clientAddr, &len);
        if (clientSock < 0) {
            sleep(1);
            continue;
        }
        NSLog(@"[RemoteControllerDaemon] New Unix client: %d", clientSock);
        @synchronized (self.unixClients) {
            [self.unixClients addObject:@(clientSock)];
        }
        // If we already have controller, send connect immediately
        if (self.hasController) {
            dispatch_async(self.queue, ^{
                [self sendConnectToSingleTweak:clientSock];
            });
        }
        // Monitor disconnect
        dispatch_async(self.queue, ^{
            uint8_t buf[1];
            while (recv(clientSock, buf, 1, 0) > 0) {
                // We don't expect data from tweaks except player index
            }
            NSLog(@"[RemoteControllerDaemon] Unix client disconnected: %d", clientSock);
            close(clientSock);
            @synchronized (self.unixClients) {
                [self.unixClients removeObject:@(clientSock)];
            }
        });
    }
}

- (void)sendConnectToTweaks {
    RCInternalPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.size = sizeof(pkt);
    pkt.type = RCPacketTypeConnect;
    pkt.handle = self.controllerHandle;
    strncpy(pkt.connect.vendorName, "Remote Controller", sizeof(pkt.connect.vendorName)-1);
    pkt.connect.presentControls = 0xFFFF;
    pkt.connect.analogControls = 0xFFFF;
    NSData *data = [NSData dataWithBytes:&pkt length:sizeof(pkt)];
    [self broadcastToUnixClients:data];
}

- (void)sendConnectToSingleTweak:(int)sock {
    RCInternalPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.size = sizeof(pkt);
    pkt.type = RCPacketTypeConnect;
    pkt.handle = self.controllerHandle;
    strncpy(pkt.connect.vendorName, "Remote Controller", sizeof(pkt.connect.vendorName)-1);
    pkt.connect.presentControls = 0xFFFF;
    pkt.connect.analogControls = 0xFFFF;
    send(sock, &pkt, sizeof(pkt), 0);
}

- (void)sendDisconnectToTweaks {
    RCInternalPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.size = sizeof(pkt);
    pkt.type = RCPacketTypeDisconnect;
    pkt.handle = self.controllerHandle;
    NSData *data = [NSData dataWithBytes:&pkt length:sizeof(pkt)];
    [self broadcastToUnixClients:data];
}

- (void)sendInputToTweaks:(RemoteControllerPacket)input {
    RCInternalPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.size = sizeof(pkt);
    pkt.type = RCPacketTypeInputState;
    pkt.handle = self.controllerHandle;
    pkt.input = input;
    NSData *data = [NSData dataWithBytes:&pkt length:sizeof(pkt)];
    [self broadcastToUnixClients:data];
}

- (void)broadcastToUnixClients:(NSData*)data {
    @synchronized (self.unixClients) {
        for (NSNumber *num in [self.unixClients copy]) {
            int sock = [num intValue];
            ssize_t sent = send(sock, data.bytes, data.length, 0);
            if (sent < 0) {
                NSLog(@"[RemoteControllerDaemon] Failed to send to unix client %d: %s", sock, strerror(errno));
            }
        }
    }
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"[RemoteControllerDaemon] Bonjour published: %@", sender.name);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"[RemoteControllerDaemon] Bonjour failed to publish: %@", errorDict);
}

@end
