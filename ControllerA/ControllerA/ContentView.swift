import SwiftUI

struct ContentView: View {
    @StateObject var inputState = InputState()
    @StateObject var connection = ConnectionManager()
    @StateObject var settings = SettingsManager()
    @State private var showConnectionSheet = false
    @State private var showSettingsSheet = false
    @State private var manualHost = ""
    @State private var isLandscape = false

    var body: some View {
        ZStack {
            ControllerView(input: inputState)

            // Overlay HUD
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connection.state == .connected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(connection.state == .connected ? "Connected to \(connection.connectedHost ?? "")" : "Disconnected")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                        if connection.state == .connected && settings.showDiagnostics {
                            Text("RTT: \(connection.rttMs)ms | Loss: \(String(format: "%.1f", connection.packetLoss))% | \(Int(connection.sendRate))Hz")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)

                    Spacer()

                    HStack(spacing: 10) {
                        Button(action: { showSettingsSheet = true }) {
                            Image(systemName: "gear")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        Button(action: { showConnectionSheet = true }) {
                            Image(systemName: "wifi")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            connection.setInputState(inputState)
            connection.startDiscovery()
        }
        .sheet(isPresented: $showConnectionSheet) {
            connectionSheet
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(settings: settings, connection: connection)
        }
    }

    var connectionSheet: some View {
        NavigationView {
            List {
                Section(header: Text("Status")) {
                    Text("State: \(String(describing: connection.state))")
                    if let host = connection.connectedHost {
                        Text("Connected: \(host)")
                    }
                }

                Section(header: Text("Discovered Devices")) {
                    if connection.discoveredServices.isEmpty {
                        Text("No devices found. Ensure iPhone B daemon is running and both on same Wi-Fi.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ForEach(connection.discoveredServices, id: \.name) { service in
                            Button(action: {
                                connection.connect(to: service)
                                showConnectionSheet = false
                            }) {
                                VStack(alignment: .leading) {
                                    Text(service.name).font(.body)
                                    Text("\(service.hostName ?? "resolving..."):\(service.port)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Manual Connection")) {
                    HStack {
                        TextField("IP Address (e.g. 192.168.1.10)", text: $manualHost)
                            .keyboardType(.decimalPad)
                        Button("Connect") {
                            guard !manualHost.isEmpty else { return }
                            connection.connect(to: manualHost)
                            showConnectionSheet = false
                        }
                    }
                }

                Section(header: Text("Diagnostics")) {
                    Button(connection.state == .connected ? "Disconnect" : "Start Discovery") {
                        if connection.state == .connected {
                            connection.disconnect()
                        } else {
                            connection.startDiscovery()
                        }
                    }
                }

                Section(header: Text("Instructions")) {
                    Text("1. Jailbreak iPhone B and install RemoteController.deb\n2. Ensure daemon is running (check Settings or via terminal)\n3. Both iPhones on same Wi-Fi\n4. iPhone B will advertise via Bonjour\n5. Connect from this list or enter IP manually\n6. Open Stardew Valley on iPhone B and controller should be detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Connection")
            .navigationBarItems(trailing: Button("Done") { showConnectionSheet = false })
        }
    }
}
