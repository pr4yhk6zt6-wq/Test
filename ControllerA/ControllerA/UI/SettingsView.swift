import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var connection: ConnectionManager

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Controller")) {
                    VStack(alignment: .leading) {
                        Text("Deadzone: \(String(format: "%.2f", settings.deadzone))")
                        Slider(value: Binding(
                            get: { Double(settings.deadzone) },
                            set: { settings.deadzone = Float($0) }
                        ), in: 0...0.5, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(String(format: "%.1f", settings.sensitivity))")
                        Slider(value: Binding(
                            get: { Double(settings.sensitivity) },
                            set: { settings.sensitivity = Float($0) }
                        ), in: 0.5...2.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Send Rate: \(Int(settings.sendRate))Hz")
                        Slider(value: Binding(
                            get: { Double(settings.sendRate) },
                            set: { settings.sendRate = Float($0) }
                        ), in: 30...120, step: 10)
                    }
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    Toggle("Show Diagnostics", isOn: $settings.showDiagnostics)
                }

                Section(header: Text("Connection")) {
                    Text("State: \(String(describing: connection.state))")
                    if let host = connection.connectedHost {
                        Text("Host: \(host)")
                    }
                    Text("RTT: \(connection.rttMs)ms")
                    Text("Packet Loss: \(String(format: "%.1f", connection.packetLoss))%")
                    Text("Send Rate: \(String(format: "%.0f", connection.sendRate))Hz")
                }

                Section(header: Text("About")) {
                    Text("Remote Controller v1.0")
                    Text("iPhone A as controller for iPhone B")
                    Text("Requires jailbreak on iPhone B")
                    Link("Architecture Docs", destination: URL(string: "https://github.com/pr4yhk6zt6-wq/Test/blob/arena/01a0dea2-test/docs/ARCHITECTURE.md")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
