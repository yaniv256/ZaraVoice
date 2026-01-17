import Foundation

class SSEClient: ObservableObject {
    static let shared = SSEClient()

    @Published var isConnected = false
    @Published var latestNotification: AudioNotification?
    @Published var lastError: String?

    private var streamTask: Task<Void, Never>?
    private let url = URL(string: "https://agent-flow.net/zara/audio-stream")!

    private init() {}

    func connect() {
        guard streamTask == nil else {
            print("[SSE] Already connected")
            return
        }

        streamTask = Task {
            await startStreaming()
        }
    }

    private func startStreaming() async {
        guard let token = UserDefaults.standard.string(forKey: "auth_token") else {
            print("[SSE] WARNING: No auth token found!")
            await MainActor.run {
                self.lastError = "No auth token"
                self.isConnected = false
            }
            return
        }

        print("[SSE] Starting stream with auth token")

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SSE] Invalid response type")
                await reconnect()
                return
            }

            print("[SSE] Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                print("[SSE] Unauthorized - signing out")
                await MainActor.run {
                    AuthManager.shared.signOut()
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("[SSE] Bad status: \(httpResponse.statusCode)")
                await MainActor.run {
                    self.lastError = "HTTP \(httpResponse.statusCode)"
                    self.isConnected = false
                }
                await reconnect()
                return
            }

            await MainActor.run {
                self.isConnected = true
                self.lastError = nil
            }

            print("[SSE] Connected! Reading lines...")

            // Read lines as they arrive
            for try await line in bytes.lines {
                if Task.isCancelled { break }

                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    print("[SSE] Received: \(jsonString.prefix(80))...")

                    if let jsonData = jsonString.data(using: .utf8),
                       let notification = try? JSONDecoder().decode(AudioNotification.self, from: jsonData) {
                        print("[SSE] Parsed notification: msg_id=\(notification.msgId ?? "nil")")
                        await MainActor.run {
                            self.latestNotification = notification
                        }
                    }
                }
            }

            print("[SSE] Stream ended normally")
            await MainActor.run {
                self.isConnected = false
            }
            await reconnect()

        } catch {
            if Task.isCancelled {
                print("[SSE] Task cancelled")
                return
            }
            print("[SSE] Error: \(error.localizedDescription)")
            await MainActor.run {
                self.isConnected = false
                self.lastError = error.localizedDescription
            }
            await reconnect()
        }
    }

    private func reconnect() async {
        streamTask = nil
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        if !Task.isCancelled {
            print("[SSE] Reconnecting...")
            streamTask = Task {
                await startStreaming()
            }
        }
    }

    func disconnect() {
        print("[SSE] Disconnecting")
        streamTask?.cancel()
        streamTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
