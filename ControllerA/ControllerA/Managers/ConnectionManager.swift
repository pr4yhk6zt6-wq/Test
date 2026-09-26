import Foundation
import Network
import Combine

enum ConnectionState {
    case disconnected
    case discovering
    case connecting
    case connected
}

class ConnectionManager: NSObject, ObservableObject {
    @Published var state: ConnectionState = .disconnected
    @Published var discoveredServices: [NetService] = []
    @Published var connectedHost: String?
    @Published var rttMs: Int = 0
    @Published var packetLoss: Float = 0
    @Published var sendRate: Float = 0

    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var tcpConnection: NWConnection?
    private var queue = DispatchQueue(label: "rc.connection")
    private var sendTimer: Timer?
    private var lastPingTime: UInt64 = 0
    private var lastPongRtt: Int = 0
    private var sequenceSent: UInt32 = 0
    private var sequenceAcked: UInt32 = 0
    private var manualHost: String?
    private var inputState: InputState?

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    func setInputState(_ state: InputState) {
        self.inputState = state
    }

    func startDiscovery() {
        state = .discovering
        discoveredServices = []
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: RC_BONJOUR_TYPE, inDomain: "local.")
        print("[Connection] Starting Bonjour discovery for \(RC_BONJOUR_TYPE)")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        for s in resolvingServices {
            s.stop()
        }
        resolvingServices = []
    }

    func connect(to host: String, port: UInt16 = RC_PORT) {
        manualHost = host
        stopDiscovery()
        state = .connecting
        print("[Connection] Connecting to \(host):\(port)")
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.tcpConnection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                switch newState {
                case .ready:
                    self?.state = .connected
                    self?.connectedHost = host
                    print("[Connection] Connected to \(host)")
                    self?.onConnected?()
                    self?.startReceiving()
                    self?.startSending()
                case .failed(let error):
                    print("[Connection] Failed: \(error)")
                    self?.state = .disconnected
                    self?.scheduleReconnect()
                case .cancelled:
                    print("[Connection] Cancelled")
                    self?.state = .disconnected
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    func connect(to service: NetService) {
        guard let host = service.hostName else {
            print("[Connection] No hostName for service")
            return
        }
        let port = UInt16(service.port)
        connect(to: host, port: port)
    }

    func disconnect() {
        sendTimer?.invalidate()
        sendTimer = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        state = .disconnected
        connectedHost = nil
        onDisconnected?()
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, let host = self.manualHost else {
                self?.startDiscovery()
                return
            }
            self.connect(to: host)
        }
    }

    private func startSending() {
        sendTimer?.invalidate()
        sendTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.sendCurrentState()
        }
    }

    private func sendCurrentState() {
        guard let input = inputState, let conn = tcpConnection else { return }
        let packet = input.toPacket()
        let data = packet.toData()
        // length prefix 4 bytes
        var len = UInt32(data.count).littleEndian
        var sendData = Data(bytes: &len, count: 4)
        sendData.append(data)
        conn.send(content: sendData, completion: .contentProcessed { error in
            if let error = error {
                print("[Connection] Send error: \(error)")
            }
        })
        sequenceSent = packet.sequence
    }

    private func startReceiving() {
        guard let conn = tcpConnection else { return }
        receiveNext(conn)
    }

    private func receiveNext(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4 else {
                if let error = error {
                    print("[Connection] Receive length error: \(error)")
                    self?.disconnect()
                }
                return
            }
            let len = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            conn.receive(minimumIncompleteLength: Int(len), maximumLength: Int(len)) { data2, _, _, error in
                if let data2 = data2 {
                    self.handleReceivedData(data2)
                }
                if error == nil {
                    self.receiveNext(conn)
                } else {
                    print("[Connection] Receive error: \(String(describing: error))")
                    self.disconnect()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        // Handle pong or ack
        if data.count >= 8 {
            let magic = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            if magic == RC_MAGIC {
                // Could be pong
                // For now ignore
            }
        }
    }

    func setManualHost(_ host: String) {
        manualHost = host
    }
}

extension ConnectionManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[Discovery] Found service: \(service.name)")
        service.delegate = self
        service.resolve(withTimeout: 5)
        resolvingServices.append(service)
        if !moreComing {
            DispatchQueue.main.async {
                // Update UI
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        DispatchQueue.main.async {
            self.discoveredServices.removeAll { $0.name == service.name }
        }
    }
}

extension ConnectionManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        DispatchQueue.main.async {
            if !self.discoveredServices.contains(where: { $0.name == sender.name }) {
                self.discoveredServices.append(sender)
            }
            print("[Discovery] Resolved \(sender.name) -> \(sender.hostName ?? "unknown"):\(sender.port)")
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Discovery] Failed to resolve \(sender.name): \(errorDict)")
    }
}
