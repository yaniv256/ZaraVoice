import Foundation

class APIService {
    static let shared = APIService()
    private let baseURL = "https://agent-flow.net/zara"

    private init() {}
    
    // Get auth token from AuthManager
    private var authToken: String? {
        UserDefaults.standard.string(forKey: "auth_token")
    }
    
    // Add auth header to request
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Transcribe Audio
    func transcribe(audioData: Data) async throws -> TranscriptionResponse {
        let url = URL(string: "\(baseURL)/transcribe")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    // MARK: - Upload Screenshot
    func uploadScreenshot(imageData: Data, type: String, source: String) async throws -> UploadResponse {
        let url = URL(string: "\(baseURL)/screen-share")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let info: [String: Any] = [
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": source
        ]
        let infoJSON = try JSONSerialization.data(withJSONObject: info)

        var body = Data()

        // Screenshot file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"capture.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Info JSON
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"info\"\r\n\r\n".data(using: .utf8)!)
        body.append(infoJSON)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    // MARK: - Upload Debug Screenshot
    func uploadDebugScreenshot(imageData: Data, logs: [String], elements: [[String: Any]]) async throws -> UploadResponse {
        let url = URL(string: "\(baseURL)/debug-upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Screenshot
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"debug.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Logs
        let logsJSON = try JSONSerialization.data(withJSONObject: logs)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"logs\"\r\n\r\n".data(using: .utf8)!)
        body.append(logsJSON)
        body.append("\r\n".data(using: .utf8)!)

        // Elements
        let elementsJSON = try JSONSerialization.data(withJSONObject: elements)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"elements\"\r\n\r\n".data(using: .utf8)!)
        body.append(elementsJSON)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    // MARK: - Session History
    func getSessionHistory() async throws -> [SessionMessage] {
        let url = URL(string: "\(baseURL)/session-history")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        // Backend returns {"age": N, "messages": [...]}
        let wrapper = try JSONDecoder().decode(SessionHistoryResponse.self, from: data)
        return wrapper.messages.map { msg in
            SessionMessage(role: msg.role, content: msg.content)
        }
    }

    // MARK: - Push to Session
    func pushToSession(role: String, content: String) async throws {
        let url = URL(string: "\(baseURL)/session-push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: String] = ["role": role, "content": content]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Video Watch Control

    func startVideoWatch(context: String = "") async throws {
        let url = URL(string: "\(baseURL)/video-frame/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: String] = ["context": context]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    func stopVideoWatch() async throws {
        let url = URL(string: "\(baseURL)/video-frame/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
    }

    func uploadVideoFrame(imageData: Data) async throws -> UploadResponse {
        let url = URL(string: "\(baseURL)/video-frame")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"frame\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-logout on 401
        try checkUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }
}

enum APIError: Error {
    case requestFailed
    case invalidResponse
    case unauthorized
}

// MARK: - Session History Response
struct SessionHistoryResponse: Codable {
    let age: Int
    let messages: [SessionHistoryMessage]
}

struct SessionHistoryMessage: Codable {
    let role: String
    let content: String
    let time: String?
    let audioTs: String?
    let msgId: String?

    enum CodingKeys: String, CodingKey {
        case role, content, time
        case audioTs = "audio_ts"
        case msgId = "msg_id"
    }
}

// MARK: - Auto-logout on 401
extension APIService {
    /// Check response for 401 and trigger auto-logout if unauthorized
    func checkUnauthorized(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode == 401 {
            // Clear tokens and trigger logout on main thread
            DispatchQueue.main.async {
                UserDefaults.standard.removeObject(forKey: "auth_token")
                UserDefaults.standard.removeObject(forKey: "user_email")
                NotificationCenter.default.post(name: NSNotification.Name("UserDidLogout"), object: nil)
            }
            throw APIError.unauthorized
        }
    }
}
