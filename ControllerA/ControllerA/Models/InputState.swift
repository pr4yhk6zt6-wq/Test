import Foundation
import Combine

class InputState: ObservableObject {
    @Published var leftStickX: Float = 0
    @Published var leftStickY: Float = 0
    @Published var rightStickX: Float = 0
    @Published var rightStickY: Float = 0
    @Published var dpadX: Float = 0
    @Published var dpadY: Float = 0
    @Published var buttons: RCButtons = []
    @Published var leftTrigger: Float = 0
    @Published var rightTrigger: Float = 0

    var sequence: UInt32 = 0

    func toPacket() -> RemoteControllerPacket {
        sequence &+= 1
        return RemoteControllerPacket(
            magic: RC_MAGIC,
            version: RC_VERSION,
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            sequence: sequence,
            leftStickX: leftStickX,
            leftStickY: leftStickY,
            rightStickX: rightStickX,
            rightStickY: rightStickY,
            dpadX: dpadX,
            dpadY: dpadY,
            buttons: buttons.rawValue,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            reserved: 0
        )
    }

    func reset() {
        leftStickX = 0
        leftStickY = 0
        rightStickX = 0
        rightStickY = 0
        dpadX = 0
        dpadY = 0
        buttons = []
        leftTrigger = 0
        rightTrigger = 0
    }
}
