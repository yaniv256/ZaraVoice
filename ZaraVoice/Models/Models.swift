import Foundation

// MARK: - Session Message
struct SessionMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    let time: String?      // Display time from server
    let msgId: String?     // For audio playback matching
    let audioTs: String?   // Legacy audio timestamp

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(), time: String? = nil, msgId: String? = nil, audioTs: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.time = time
        self.msgId = msgId
        self.audioTs = audioTs
    }

    var isUser: Bool {
        role == "user"
    }

    var isZaraVoice: Bool {
        role == "zara_voice"
    }

    /// Returns true if this message has playable audio
    var hasAudio: Bool {
        // Zara voice messages use msg_id
        // User messages can use msg_id (new) or audio_ts (legacy)
        if isZaraVoice && msgId != nil { return true }
        if isUser && (msgId != nil || audioTs != nil) { return true }
        return false
    }

    /// Get the audio URL for this message
    func getAudioURL(baseURL: String) -> URL? {
        guard hasAudio else { return nil }

        if isUser {
            // User audio
            if let msgId = msgId {
                return URL(string: "\(baseURL)/user-audio?m=\(msgId)")
            }
            if let audioTs = audioTs {
                return URL(string: "\(baseURL)/user-audio?t=\(audioTs)")
            }
        } else {
            // Zara audio (zara_voice or assistant)
            if let msgId = msgId {
                return URL(string: "\(baseURL)/zara-response?m=\(msgId)")
            }
            if let audioTs = audioTs {
                return URL(string: "\(baseURL)/zara-response?t=\(audioTs)")
            }
        }
        return nil
    }
}

// MARK: - Audio Notification (from SSE)
struct AudioNotification: Codable, Equatable {
    let time: String
    let name: String
    let msgId: String?
    let text: String?
    let chunk: Int?

    enum CodingKeys: String, CodingKey {
        case time
        case name
        case msgId = "msg_id"
        case text
        case chunk
    }
}

// MARK: - Transcription Response
// Backend returns dual transcription: medium.en + WhisperX small.en with speaker diarization
struct TranscriptionResponse: Codable {
    let text: String?                    // Final transcription to use
    let rawText: String?                 // Raw transcription for "show raw" toggle
    let whisperText: String?             // medium.en transcription (quality)
    let elevenLabsText: String?          // WhisperX small.en with speaker tags
    let divergence: Bool?                // True if models diverged significantly
    let similarity: Double?              // Embedding similarity between transcriptions
    let confidence: String?              // "high", "medium", or "noise"
    let speakerScore: Double?            // Speaker verification score (0-1)
    let filtered: String?                // "noise", "hallucination", "low_energy", "speaker_mismatch"
    let audioTs: String?                 // Human-readable timestamp
    let msgId: String?                   // Message ID for audio matching
    let status: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case text
        case rawText = "raw_text"
        case whisperText = "whisper_text"
        case elevenLabsText = "elevenlabs_text"
        case divergence
        case similarity
        case confidence
        case speakerScore = "speaker_score"
        case filtered
        case audioTs = "audio_ts"
        case msgId = "msg_id"
        case status
        case error
    }

    // Check if this was filtered out (noise, hallucination, etc.)
    var wasFiltered: Bool {
        filtered != nil && (text?.isEmpty ?? true)
    }
}

// MARK: - Upload Response
struct UploadResponse: Codable {
    let status: String
    let filename: String?
    let error: String?
}

// MARK: - App Settings
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }
    @Published var silenceDuration: Double {
        didSet { UserDefaults.standard.set(silenceDuration, forKey: "silenceDuration") }
    }
    @Published var silenceThreshold: Double {
        didSet { UserDefaults.standard.set(silenceThreshold, forKey: "silenceThreshold") }
    }
    @Published var minSpeechDuration: Double {
        didSet { UserDefaults.standard.set(minSpeechDuration, forKey: "minSpeechDuration") }
    }
    @Published var prerollDuration: Double {
        didSet { UserDefaults.standard.set(prerollDuration, forKey: "prerollDuration") }
    }
    @Published var energyThreshold: Double {
        didSet { UserDefaults.standard.set(energyThreshold, forKey: "energyThreshold") }
    }

    private init() {
        sensitivity = UserDefaults.standard.double(forKey: "sensitivity").nonZeroOr(20)
        silenceDuration = UserDefaults.standard.double(forKey: "silenceDuration").nonZeroOr(5.0)
        silenceThreshold = UserDefaults.standard.double(forKey: "silenceThreshold").nonZeroOr(5)
        minSpeechDuration = UserDefaults.standard.double(forKey: "minSpeechDuration").nonZeroOr(0.3)
        prerollDuration = UserDefaults.standard.double(forKey: "prerollDuration").nonZeroOr(2.0)
        energyThreshold = UserDefaults.standard.double(forKey: "energyThreshold").nonZeroOr(0.01)
    }
}

extension Double {
    func nonZeroOr(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}
