import Foundation

let RC_MAGIC: UInt32 = 0x52435044
let RC_VERSION: UInt32 = 1
let RC_PORT: UInt16 = 9944
let RC_BONJOUR_TYPE = "_remotegamepad._tcp"

struct RCButtons: OptionSet {
    let rawValue: UInt32
    static let a = RCButtons(rawValue: 1 << 0)
    static let b = RCButtons(rawValue: 1 << 1)
    static let x = RCButtons(rawValue: 1 << 2)
    static let y = RCButtons(rawValue: 1 << 3)
    static let l1 = RCButtons(rawValue: 1 << 4)
    static let r1 = RCButtons(rawValue: 1 << 5)
    static let l2 = RCButtons(rawValue: 1 << 6)
    static let r2 = RCButtons(rawValue: 1 << 7)
    static let menu = RCButtons(rawValue: 1 << 8)
    static let view = RCButtons(rawValue: 1 << 9)
    static let l3 = RCButtons(rawValue: 1 << 10)
    static let r3 = RCButtons(rawValue: 1 << 11)
}

struct RemoteControllerPacket {
    var magic: UInt32 = RC_MAGIC
    var version: UInt32 = RC_VERSION
    var timestampMs: UInt64 = 0
    var sequence: UInt32 = 0
    var leftStickX: Float = 0
    var leftStickY: Float = 0
    var rightStickX: Float = 0
    var rightStickY: Float = 0
    var dpadX: Float = 0
    var dpadY: Float = 0
    var buttons: UInt32 = 0
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    var reserved: UInt32 = 0

    func toData() -> Data {
        var data = Data()
        func append<T>(_ value: T) {
            var v = value
            data.append(Data(bytes: &v, count: MemoryLayout<T>.size))
        }
        append(magic.littleEndian)
        append(version.littleEndian)
        append(timestampMs.littleEndian)
        append(sequence.littleEndian)
        append(leftStickX)
        append(leftStickY)
        append(rightStickX)
        append(rightStickY)
        append(dpadX)
        append(dpadY)
        append(buttons.littleEndian)
        append(leftTrigger)
        append(rightTrigger)
        append(reserved.littleEndian)
        return data
    }

    static func fromData(_ data: Data) -> RemoteControllerPacket? {
        guard data.count >= 60 else { return nil }
        var offset = 0
        func read<T>(_: T.Type) -> T {
            let size = MemoryLayout<T>.size
            let value = data[offset..<offset+size].withUnsafeBytes { $0.load(as: T.self) }
            offset += size
            return value
        }
        var pkt = RemoteControllerPacket()
        pkt.magic = read(UInt32.self).littleEndian
        pkt.version = read(UInt32.self).littleEndian
        pkt.timestampMs = read(UInt64.self).littleEndian
        pkt.sequence = read(UInt32.self).littleEndian
        pkt.leftStickX = read(Float.self)
        pkt.leftStickY = read(Float.self)
        pkt.rightStickX = read(Float.self)
        pkt.rightStickY = read(Float.self)
        pkt.dpadX = read(Float.self)
        pkt.dpadY = read(Float.self)
        pkt.buttons = read(UInt32.self).littleEndian
        pkt.leftTrigger = read(Float.self)
        pkt.rightTrigger = read(Float.self)
        pkt.reserved = read(UInt32.self).littleEndian
        return pkt
    }
}

struct PingPacket {
    var timestampMs: UInt64
    func toData() -> Data {
        var data = Data()
        var magic = RC_MAGIC.littleEndian
        var type: UInt32 = 4 // ping
        data.append(Data(bytes: &magic, count: 4))
        data.append(Data(bytes: &type, count: 4))
        var ts = timestampMs.littleEndian
        data.append(Data(bytes: &ts, count: 8))
        return data
    }
}
