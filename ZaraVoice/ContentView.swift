import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // Main app content
                TabView(selection: $selectedTab) {
                    VoiceView()
                        .tabItem {
                            Label("Voice", systemImage: "waveform")
                        }
                        .tag(0)

                    SessionView()
                        .tabItem {
                            Label("Session", systemImage: "text.bubble")
                        }
                        .tag(1)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(2)
                }
                .tint(.purple)
            } else {
                // Login screen
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
}
