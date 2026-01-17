import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var sseClient = SSEClient.shared
    @State private var logs: [String] = []

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.18)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Connection status
                        connectionStatus

                        // Audio settings
                        settingsSection(title: "Audio Settings") {
                            SliderRow(title: "Sensitivity", value: $settings.sensitivity, range: 1...100, format: "%.0f")
                            SliderRow(title: "Silence Duration", value: $settings.silenceDuration, range: 0.5...10, format: "%.1fs")
                            SliderRow(title: "Silence Threshold", value: $settings.silenceThreshold, range: 1...20, format: "%.0f")
                            SliderRow(title: "Min Speech", value: $settings.minSpeechDuration, range: 0.1...1.0, format: "%.0fms", multiplier: 1000)
                            SliderRow(title: "Preroll Duration", value: $settings.prerollDuration, range: 0.5...5.0, format: "%.1fs")
                            SliderRow(title: "Energy Threshold", value: $settings.energyThreshold, range: 0.001...0.1, format: "%.3f")
                        }

                        // Logs section
                        settingsSection(title: "Logs") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(logs.prefix(20), id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // App info
                        settingsSection(title: "About") {
                            HStack {
                                Text("Version")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("1.7")
                                    .foregroundColor(.white)
                            }
                            HStack {
                                Text("Server")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("agent-flow.net")
                                    .foregroundColor(.white)
                            }
                        }

                        // Account section
                        settingsSection(title: "Account") {
                            if let email = UserDefaults.standard.string(forKey: "user_email") {
                                HStack {
                                    Text("Logged in as")
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text(email)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Button(action: logout) {
                                HStack {
                                    Spacer()
                                    Text("Logout")
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.1, green: 0.1, blue: 0.18), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            addLog("Settings opened")
            addLog("SSE: \(sseClient.isConnected ? "Connected" : "Disconnected")")
        }
    }

    private var connectionStatus: some View {
        HStack {
            Circle()
                .fill(sseClient.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(sseClient.isConnected ? "Connected to Zara" : "Disconnected")
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                if sseClient.isConnected {
                    sseClient.disconnect()
                } else {
                    sseClient.connect()
                }
            }) {
                Text(sseClient.isConnected ? "Disconnect" : "Connect")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.3))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(red: 0.17, green: 0.17, blue: 0.3))
        .cornerRadius(12)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.purple)

            VStack(spacing: 16) {
                content()
            }
            .padding()
            .background(Color(red: 0.17, green: 0.17, blue: 0.3))
            .cornerRadius(12)
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("\(timestamp): \(message)", at: 0)
    }

    private func logout() {
        addLog("Logging out...")

        // Disconnect SSE
        sseClient.disconnect()

        // Use AuthManager to properly sign out (clears tokens and updates isAuthenticated)
        AuthManager.shared.signOut()
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var multiplier: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: format, value * multiplier))
                    .foregroundColor(.cyan)
                    .font(.system(.body, design: .monospaced))
            }

            Slider(value: $value, in: range)
                .tint(.purple)
        }
    }
}

#Preview {
    SettingsView()
}
