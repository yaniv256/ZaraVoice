import AVFoundation
import Foundation

class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Float = 0
    @Published var status: RecordingStatus = .ready

    enum RecordingStatus: String {
        case ready = "Ready - tap Start Talking"
        case listening = "Listening..."
        case sending = "Sending..."
        case speaking = "Zara is speaking..."
        case paused = "Paused"
    }

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    // Preroll buffer
    private var prerollBuffer: [Data] = []
    private var prerollEngine: AVAudioEngine?

    override private init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Recording
    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording.wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            status = .listening

            // Start level monitoring
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() -> Data? {
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        status = .sending

        guard let url = recordingURL else { return nil }

        do {
            return try Data(contentsOf: url)
        } catch {
            print("Failed to read recording: \(error)")
            return nil
        }
    }

    private func updateAudioLevel() {
        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160
        // Convert dB to 0-1 range
        let normalizedLevel = max(0, (level + 60) / 60)
        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
    }

    // MARK: - Playback
    func playAudio(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            playAudio(data: data)
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()

            isPlaying = true
            status = .speaking
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        status = .ready
    }

    // MARK: - Fetch and Play from Server
    func playLatestAudio(timestamp: String) {
        let urlString = "https://seethegalaxy.com/audio/voice-generated/\(timestamp).mp3"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                DispatchQueue.main.async {
                    self.playAudio(data: data)
                }
            } catch {
                print("Failed to fetch audio: \(error)")
            }
        }
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.status = .ready
        }
    }
}
