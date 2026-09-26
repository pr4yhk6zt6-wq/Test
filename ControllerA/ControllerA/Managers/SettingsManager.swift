import Foundation
import Combine

class SettingsManager: ObservableObject {
    @Published var deadzone: Float = 0.15 {
        didSet { UserDefaults.standard.set(deadzone, forKey: "deadzone") }
    }
    @Published var sensitivity: Float = 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }
    @Published var sendRate: Float = 60 {
        didSet { UserDefaults.standard.set(sendRate, forKey: "sendRate") }
    }
    @Published var showDiagnostics: Bool = true {
        didSet { UserDefaults.standard.set(showDiagnostics, forKey: "showDiagnostics") }
    }
    @Published var hapticsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    init() {
        deadzone = UserDefaults.standard.object(forKey: "deadzone") as? Float ?? 0.15
        sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Float ?? 1.0
        sendRate = UserDefaults.standard.object(forKey: "sendRate") as? Float ?? 60
        showDiagnostics = UserDefaults.standard.object(forKey: "showDiagnostics") as? Bool ?? true
        hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    func applyDeadzone(_ value: Float) -> Float {
        if abs(value) < deadzone { return 0 }
        return value
    }

    func applySensitivity(_ value: Float) -> Float {
        return max(-1, min(1, value * sensitivity))
    }
}
