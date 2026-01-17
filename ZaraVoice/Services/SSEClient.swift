import Foundation
import os.log

private let logger = Logger(subsystem: "net.agentflow.ZaraVoice", category: "SSE")

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
            logger.info("[SSE] Already connected")
            return
        }

        streamTask = Task {
            await startStreaming()
        }
    }

    private func startStreaming() async {
        // Debug: Print all UserDefaults keys
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        logger.info("[SSE] UserDefaults keys: \(allKeys.sorted())")

        guard let token = UserDefaults.standard.string(forKey: "auth_token") else {
            logger.info("[SSE] WARNING: No auth token found in UserDefaults!")
            logger.info("[SSE] Available keys: \(allKeys.filter { $0.contains("auth") || $0.contains("token") })")
            await MainActor.run {
                self.lastError = "No auth token"
                self.isConnected = false
            }
            return
        }

        logger.info("[SSE] Starting stream with auth token (length: \(token.count))")

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.info("[SSE] Invalid response type")
                await reconnect()
                return
            }

            logger.info("[SSE] Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                logger.info("[SSE] Unauthorized - signing out")
                await MainActor.run {
                    AuthManager.shared.signOut()
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                logger.info("[SSE] Bad status: \(httpResponse.statusCode)")
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

            logger.info("[SSE] Connected! Reading lines...")

            // Track connection start time for debugging
            let startTime = Date()

            // Read lines as they arrive
            for try await line in bytes.lines {
                if Task.isCancelled {
                    logger.info("[SSE] Task cancelled, breaking loop")
                    break
                }

                let elapsed = Date().timeIntervalSince(startTime)
                logger.info("[SSE] Line received at +\(String(format: "%.1f", elapsed))s: \(line.prefix(50))")

                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    logger.info("[SSE] Data payload: \(jsonString.prefix(80))...")

                    if let jsonData = jsonString.data(using: .utf8),
                       let notification = try? JSONDecoder().decode(AudioNotification.self, from: jsonData) {
                        logger.info("[SSE] Parsed notification: msg_id=\(notification.msgId ?? "nil")")
                        await MainActor.run {
                            self.latestNotification = notification
                        }
                    }
                }
            }

            let totalTime = Date().timeIntervalSince(startTime)
            logger.info("[SSE] Stream ended normally after \(String(format: "%.1f", totalTime))s")
            await MainActor.run {
                self.isConnected = false
            }
            await reconnect()

        } catch {
            if Task.isCancelled {
                logger.info("[SSE] Task cancelled")
                return
            }
            logger.info("[SSE] Error: \(error.localizedDescription)")
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
            logger.info("[SSE] Reconnecting...")
            streamTask = Task {
                await startStreaming()
            }
        }
    }

    func disconnect() {
        logger.info("[SSE] Disconnecting")
        streamTask?.cancel()
        streamTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
