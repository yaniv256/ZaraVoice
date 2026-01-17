import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "net.agentflow.ZaraVoice", category: "AudioManager")

class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Float = 0
    @Published var status: RecordingStatus = .ready
    @Published var normalizedLevel: Float = 0

    // Continuous listening state
    @Published var isListening = false  // Mic is open (continuous mode)
    @Published var isSpeaking = false   // User is currently speaking
    @Published var autoSendEnabled = true

    enum RecordingStatus: String {
        case ready = "Ready - tap mic to start"
        case listening = "Listening..."
        case speaking = "Speaking..."
        case silenceDetected = "Silence detected..."
        case sending = "Sending..."
        case speakingZara = "Zara is speaking..."
        case paused = "Paused"
    }

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var prerollURL: URL?  // Separate file for preroll
    private var levelTimer: Timer?

    // Preroll - rolling buffer of recent audio
    private var prerollBuffer: [Float] = []
    private let prerollSeconds: Double = 2.0  // 2 seconds of preroll
    private var prerollSampleRate: Double = 16000

    // Audio queue - holds notifications that arrive during recording
    private var audioQueue: [AudioNotification] = []

    // Silence detection
    private var silenceStart: Date?
    private var speechStart: Date?
    private var settings = AppSettings.shared

    // Callbacks
    var onChunkReady: ((Data) -> Void)?  // Called when a chunk is ready to send

    // Calibration state
    @Published var isCalibrating = false
    @Published var calibrationStep = 0
    @Published var calibrationProgress: Float = 0
    @Published var calibrationMessage = ""
    private var ambientLevels: [Float] = []
    private var speechLevels: [Float] = []
    private var longestNoiseBurst: TimeInterval = 0
    private var calibrationTimer: Timer?
    private var noiseStart: Date?

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
            logger.error("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Continuous Listening Mode (like web app)

    /// Start continuous listening - mic stays open until explicitly stopped
    func startListening() {
        // If audio is playing, stop it first
        if isPlaying {
            stopPlayback()
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording.wav")
        prerollURL = documentsPath.appendingPathComponent("preroll.wav")

        // Clear preroll buffer
        prerollBuffer = []

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: recordSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isListening = true
            isRecording = true
            isSpeaking = false
            silenceStart = nil
            speechStart = nil
            status = .listening

            // Start level monitoring and preroll capture
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.monitorAudioLevel()
            }

            logger.info("Continuous listening started with \(self.prerollSeconds)s preroll buffer")
        } catch {
            logger.error("Failed to start listening: \(error.localizedDescription)")
        }
    }

    /// Stop continuous listening - closes mic
    func stopListening() {
        levelTimer?.invalidate()
        levelTimer = nil

        // If we were speaking, send the final chunk
        if isSpeaking, let url = recordingURL {
            audioRecorder?.stop()
            if let data = try? Data(contentsOf: url) {
                onChunkReady?(data)
            }
        } else {
            audioRecorder?.stop()
        }

        isListening = false
        isRecording = false
        isSpeaking = false
        silenceStart = nil
        speechStart = nil
        status = .ready
        prerollBuffer = []

        // Play any queued audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playQueuedAudio()
        }

        logger.info("Continuous listening stopped")
    }

    private func monitorAudioLevel() {
        audioRecorder?.updateMeters()
        let dbLevel = audioRecorder?.averagePower(forChannel: 0) ?? -160

        let level = max(0, min(100, (dbLevel + 60) * (100.0 / 60.0)))

        // Update preroll buffer with simulated samples (we don't have raw PCM access)
        // The actual recording file will have the audio, we use preroll conceptually
        // by starting recording early and trimming in the web backend

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.audioLevel = max(0, (dbLevel + 60) / 60)
            self.normalizedLevel = level

            // Skip silence detection if disabled or playing
            guard self.autoSendEnabled && !self.isPlaying else { return }

            let now = Date()
            let speechThreshold = Float(self.settings.sensitivity)
            let silenceThreshold = Float(self.settings.silenceThreshold)
            let silenceDuration = self.settings.silenceDuration
            let minSpeechDuration = self.settings.minSpeechDuration

            if level > speechThreshold {
                // Speech detected
                if !self.isSpeaking {
                    self.isSpeaking = true
                    self.speechStart = now
                    self.status = .speaking
                    logger.debug("Speech started at level \(level)")
                }
                self.silenceStart = nil
            } else if level < silenceThreshold && self.isSpeaking {
                // Silence during speech
                if self.silenceStart == nil {
                    self.silenceStart = now
                    self.status = .silenceDetected
                } else if let silenceStart = self.silenceStart {
                    let silencedFor = now.timeIntervalSince(silenceStart)

                    if silencedFor > silenceDuration {
                        if let speechStart = self.speechStart {
                            let speechDuration = now.timeIntervalSince(speechStart) - silenceDuration

                            if speechDuration > minSpeechDuration {
                                logger.info("Sending chunk after \(String(format: "%.1f", silencedFor))s silence")
                                self.sendCurrentChunkAndContinue()
                            } else {
                                logger.debug("Speech too short, resetting")
                            }
                        }

                        // Reset for next utterance (but keep listening!)
                        self.isSpeaking = false
                        self.silenceStart = nil
                        self.speechStart = nil
                        self.status = .listening
                    }
                }
            }
        }
    }

    /// Send the current recording and restart recording for next utterance
    private func sendCurrentChunkAndContinue() {
        guard let url = recordingURL else { return }

        // Stop current recording
        audioRecorder?.stop()

        // Read the data
        if let data = try? Data(contentsOf: url) {
            status = .sending
            onChunkReady?(data)
        }

        // Immediately restart recording for next utterance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if self.isListening {
                self.restartRecording()
            }
        }
    }

    private func restartRecording() {
        guard let url = recordingURL else { return }

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isSpeaking = false
            silenceStart = nil
            speechStart = nil
            status = .listening

            logger.debug("Recording restarted for next utterance")
        } catch {
            logger.error("Failed to restart recording: \(error.localizedDescription)")
        }
    }

    // MARK: - Legacy single-shot recording (for manual mode)

    func startRecording() {
        startListening()
    }

    func stopRecording() -> Data? {
        guard let url = recordingURL else {
            stopListening()
            return nil
        }

        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()

        isListening = false
        isRecording = false
        isSpeaking = false
        status = .sending

        do {
            let data = try Data(contentsOf: url)

            // Play queued audio after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.playQueuedAudio()
            }

            return data
        } catch {
            logger.error("Failed to read recording: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Audio Queue Management

    private func playQueuedAudio() {
        guard !audioQueue.isEmpty else { return }
        guard !isSpeaking else { return }  // Don't play if user is speaking, but OK during silent listening

        let notification = audioQueue.removeFirst()
        logger.info("Playing queued audio, \(self.audioQueue.count) remaining")
        playAudioImmediately(notification: notification)
    }

    // MARK: - Calibration
    func startCalibration() {
        isCalibrating = true
        calibrationStep = 1
        ambientLevels = []
        speechLevels = []
        longestNoiseBurst = 0
        noiseStart = nil
        calibrationProgress = 0
        calibrationMessage = "Be quiet for 10 seconds..."

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let calibrationURL = documentsPath.appendingPathComponent("calibration.wav")

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: calibrationURL, settings: recordSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            let startTime = Date()
            calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }

                self.audioRecorder?.updateMeters()
                let dbLevel = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                let level = max(0, min(100, (dbLevel + 60) * (100.0 / 60.0)))

                let elapsed = Date().timeIntervalSince(startTime)

                DispatchQueue.main.async {
                    self.normalizedLevel = level
                    self.calibrationProgress = Float(min(1.0, elapsed / 10.0))

                    if self.calibrationStep == 1 {
                        self.ambientLevels.append(level)

                        let tempThreshold: Float = 20
                        if level > tempThreshold {
                            if self.noiseStart == nil {
                                self.noiseStart = Date()
                            }
                        } else if let noiseStart = self.noiseStart {
                            let noiseDuration = Date().timeIntervalSince(noiseStart)
                            if noiseDuration > self.longestNoiseBurst {
                                self.longestNoiseBurst = noiseDuration
                            }
                            self.noiseStart = nil
                        }

                        if elapsed >= 10 {
                            self.nextCalibrationStep()
                        }
                    } else if self.calibrationStep == 2 {
                        self.speechLevels.append(level)

                        if elapsed >= 10 {
                            self.finishCalibration()
                        }
                    }
                }
            }
        } catch {
            logger.error("Failed to start calibration: \(error.localizedDescription)")
            cancelCalibration()
        }
    }

    func nextCalibrationStep() {
        calibrationStep = 2
        calibrationProgress = 0
        calibrationMessage = "Now speak naturally for 10 seconds..."
        speechLevels = []

        calibrationTimer?.invalidate()
        let startTime = Date()

        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            self.audioRecorder?.updateMeters()
            let dbLevel = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            let level = max(0, min(100, (dbLevel + 60) * (100.0 / 60.0)))

            let elapsed = Date().timeIntervalSince(startTime)

            DispatchQueue.main.async {
                self.normalizedLevel = level
                self.calibrationProgress = Float(min(1.0, elapsed / 10.0))
                self.speechLevels.append(level)

                if elapsed >= 10 {
                    self.finishCalibration()
                }
            }
        }
    }

    private func finishCalibration() {
        calibrationTimer?.invalidate()
        audioRecorder?.stop()

        let avgAmbient = ambientLevels.isEmpty ? 10.0 : Double(ambientLevels.reduce(0, +)) / Double(ambientLevels.count)
        let avgSpeech = speechLevels.isEmpty ? 30.0 : Double(speechLevels.reduce(0, +)) / Double(speechLevels.count)

        let optimalSensitivity = (avgAmbient + avgSpeech) / 2
        let optimalSilenceThreshold = avgAmbient * 1.2 + 2

        settings.sensitivity = max(5, min(100, optimalSensitivity))
        settings.silenceThreshold = max(5, min(50, optimalSilenceThreshold))

        let optimalMinSpeech = max(0.1, min(0.5, longestNoiseBurst + 0.1))
        settings.minSpeechDuration = optimalMinSpeech

        calibrationStep = 3
        calibrationMessage = String(format: "Done! Sensitivity: %.0f, Threshold: %.0f",
                                    settings.sensitivity, settings.silenceThreshold)

        logger.info("Calibration complete")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isCalibrating = false
            self?.calibrationStep = 0
        }
    }

    func cancelCalibration() {
        calibrationTimer?.invalidate()
        audioRecorder?.stop()
        isCalibrating = false
        calibrationStep = 0
    }

    // MARK: - Playback
    func playAudio(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            playAudioData(data: data)
        } catch {
            logger.error("Failed to load audio: \(error.localizedDescription)")
        }
    }

    private func playAudioData(data: Data) {
        // Pause recording while playing to prevent echo capture
        if isListening {
            audioRecorder?.pause()
            logger.debug("Paused recording for playback")
        }

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()

            isPlaying = true
            status = .speakingZara
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            // Resume recording if playback failed
            if isListening {
                audioRecorder?.record()
            }
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        status = isListening ? .listening : .ready
    }

    // MARK: - Fetch and Play from Server

    func playAudio(notification: AudioNotification) {
        // Queue if:
        // 1. User is actively speaking (don't interrupt their speech)
        // 2. Audio is already playing (chunks must wait for each other)
        if isSpeaking || isPlaying {
            audioQueue.append(notification)
            let reason = isSpeaking ? "speech" : "playback"
            logger.info("Audio queued during \(reason), queue size: \(self.audioQueue.count)")
        } else {
            playAudioImmediately(notification: notification)
        }
    }

    private func playAudioImmediately(notification: AudioNotification) {
        let urlString: String
        if let msgId = notification.msgId {
            let chunk = notification.chunk ?? 0
            urlString = "https://agent-flow.net/zara/zara-response?m=\(msgId)&c=\(chunk)"
        } else {
            urlString = "https://agent-flow.net/zara/zara-response?t=\(notification.time)"
        }

        guard let url = URL(string: urlString) else {
            logger.error("Invalid audio URL")
            playQueuedAudio()
            return
        }

        logger.info("Fetching audio from: \(urlString)")

        var request = URLRequest(url: url)
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        logger.error("Audio fetch failed: \(httpResponse.statusCode)")
                        await MainActor.run { self.playQueuedAudio() }
                        return
                    }
                }
                if data.count < 1000 {
                    logger.warning("Audio too small: \(data.count) bytes")
                    await MainActor.run { self.playQueuedAudio() }
                    return
                }
                await MainActor.run {
                    self.playAudioData(data: data)
                }
            } catch {
                logger.error("Audio fetch error: \(error.localizedDescription)")
                await MainActor.run { self.playQueuedAudio() }
            }
        }
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying = false

            // Check if there's more audio to play
            if !self.audioQueue.isEmpty {
                // More chunks - play next (stay paused if recording)
                self.playQueuedAudio()
            } else {
                // No more audio - resume recording if we were listening
                if self.isListening {
                    self.audioRecorder?.record()
                    self.logger.debug("Resumed recording after all playback complete")
                }
                self.status = self.isListening ? .listening : .ready
            }
        }
    }
}
