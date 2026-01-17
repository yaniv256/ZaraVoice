import Foundation

class SSEClient: ObservableObject {
    static let shared = SSEClient()

    @Published var isConnected = false
    @Published var latestNotification: AudioNotification?
    @Published var lastError: String?

    private var task: URLSessionDataTask?
    private let url = URL(string: "https://agent-flow.net/zara/audio-stream")!

    private init() {}

    func connect() {
        guard task == nil else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval(Int.max)

        // Add auth token
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("[SSE] Connecting with auth token")
        } else {
            print("[SSE] WARNING: No auth token found!")
            DispatchQueue.main.async {
                self.lastError = "No auth token"
            }
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(Int.max)
        config.timeoutIntervalForResource = TimeInterval(Int.max)

        let session = URLSession(configuration: config, delegate: SSEDelegate(client: self), delegateQueue: nil)
        task = session.dataTask(with: request)
        task?.resume()
        print("[SSE] Task started")
    }

    func disconnect() {
        task?.cancel()
        task = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
        print("[SSE] Disconnected")
    }

    fileprivate func handleResponse(_ response: URLResponse?) {
        if let httpResponse = response as? HTTPURLResponse {
            print("[SSE] Response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.lastError = nil
                }
            } else {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = "HTTP \(httpResponse.statusCode)"
                }
                // If unauthorized, trigger logout
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async {
                        AuthManager.shared.signOut()
                    }
                }
            }
        }
    }

    fileprivate func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        print("[SSE] Received: \(text.prefix(100))")

        // Parse SSE format
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let jsonData = jsonString.data(using: .utf8),
                   let notification = try? JSONDecoder().decode(AudioNotification.self, from: jsonData) {
                    print("[SSE] Parsed notification: msg_id=\(notification.msgId ?? "nil")")
                    DispatchQueue.main.async {
                        self.latestNotification = notification
                    }
                }
            }
        }
    }

    fileprivate func handleError(_ error: Error?) {
        print("[SSE] Error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription
        }
        // Reconnect after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.task = nil
            self.connect()
        }
    }
}

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    weak var client: SSEClient?

    init(client: SSEClient) {
        self.client = client
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("[SSE] didReceive response")
        client?.handleResponse(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.handleData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        client?.handleError(error)
    }
}
