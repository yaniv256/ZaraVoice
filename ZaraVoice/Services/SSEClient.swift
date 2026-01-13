import Foundation

class SSEClient: ObservableObject {
    static let shared = SSEClient()

    @Published var isConnected = false
    @Published var latestNotification: AudioNotification?

    private var task: URLSessionDataTask?
    private let url = URL(string: "https://agent-flow.net/zara/audio-stream")!

    private init() {}

    func connect() {
        guard task == nil else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval(Int.max)

        let session = URLSession(configuration: .default, delegate: SSEDelegate(client: self), delegateQueue: nil)
        task = session.dataTask(with: request)
        task?.resume()

        DispatchQueue.main.async {
            self.isConnected = true
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    fileprivate func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // Parse SSE format
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let jsonData = jsonString.data(using: .utf8),
                   let notification = try? JSONDecoder().decode(AudioNotification.self, from: jsonData) {
                    DispatchQueue.main.async {
                        self.latestNotification = notification
                    }
                }
            }
        }
    }

    fileprivate func handleError(_ error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.handleData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        client?.handleError(error)
    }
}
