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
    @Published var normalizedLevel: Float = 0  // 0-100 scale for UI
    
    // Silence detection state
    @Published var isSpeaking = false
    @Published var autoSendEnabled = true
    
    enum RecordingStatus: String {
        case ready = "Ready - tap mic to talk"
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
    private var levelTimer: Timer?
    
    // Silence detection
    private var silenceStart: Date?
    private var speechStart: Date?
    private var settings = AppSettings.shared
    
    // Callback for auto-send
    var onAutoSend: (() -> Void)?
    
    // Calibration state
    @Published var isCalibrating = false
    @Published var calibrationStep = 0  // 0=idle, 1=measuring quiet, 2=measuring speech, 3=done
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
    
    // MARK: - Recording with Silence Detection
    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording.wav")
        
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
            
            isRecording = true
            isSpeaking = false
            silenceStart = nil
            speechStart = nil
            status = .listening
            
            // Start level monitoring with silence detection
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.monitorAudioLevel()
            }
            
            logger.info("Recording started with silence detection")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func monitorAudioLevel() {
        audioRecorder?.updateMeters()
        let dbLevel = audioRecorder?.averagePower(forChannel: 0) ?? -160
        
        // Convert dB to 0-100 scale similar to web app
        // dB typically ranges from -160 (silence) to 0 (max)
        // Map -60 to 0 dB → 0 to 100
        let level = max(0, min(100, (dbLevel + 60) * (100.0 / 60.0)))
        
        DispatchQueue.main.async {
            self.audioLevel = max(0, (dbLevel + 60) / 60)  // 0-1 for level bar
            self.normalizedLevel = level
            
            // Only do silence detection if auto-send is enabled
            guard self.autoSendEnabled else { return }
            
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
                        // Check minimum speech duration
                        if let speechStart = self.speechStart {
                            let speechDuration = now.timeIntervalSince(speechStart) - silenceDuration
                            
                            if speechDuration > minSpeechDuration {
                                // Auto-send!
                                logger.info("Auto-send triggered after \(String(format: "%.1f", silencedFor))s silence, speech was \(String(format: "%.1f", speechDuration))s")
                                self.triggerAutoSend()
                            } else {
                                // Too short, reset
                                logger.debug("Speech too short (\(String(format: "%.2f", speechDuration))s), resetting")
                                self.isSpeaking = false
                                self.silenceStart = nil
                                self.speechStart = nil
                                self.status = .listening
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func triggerAutoSend() {
        // Stop recording and trigger callback
        isSpeaking = false
        silenceStart = nil
        speechStart = nil
        
        onAutoSend?()
    }
    
    func stopRecording() -> Data? {
        levelTimer?.invalidate()
        levelTimer = nil
        
        audioRecorder?.stop()
        isRecording = false
        isSpeaking = false
        silenceStart = nil
        speechStart = nil
        status = .sending
        
        guard let url = recordingURL else { return nil }
        
        do {
            return try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read recording: \(error.localizedDescription)")
            return nil
        }
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
        calibrationMessage = "Be quiet for 10 seconds. Make ambient sounds (breathing, moving) but don't speak..."
        
        // Start recording for calibration
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
                        // Measuring ambient
                        self.ambientLevels.append(level)
                        
                        // Track noise bursts (non-speech sounds like coughs)
                        let tempThreshold: Float = 20  // Temporary threshold for noise detection
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
                        // Measuring speech
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
        calibrationMessage = "Now speak naturally for 10 seconds. Talk as you normally would, with natural pauses..."
        speechLevels = []
        
        // Reset timer for speech measurement
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
        
        // Calculate optimal settings
        let avgAmbient = ambientLevels.isEmpty ? 10.0 : Double(ambientLevels.reduce(0, +)) / Double(ambientLevels.count)
        let avgSpeech = speechLevels.isEmpty ? 30.0 : Double(speechLevels.reduce(0, +)) / Double(speechLevels.count)
        
        // Sensitivity: midpoint between ambient and speech
        let optimalSensitivity = (avgAmbient + avgSpeech) / 2
        
        // Silence threshold: just above ambient
        let optimalSilenceThreshold = avgAmbient * 1.2 + 2
        
        // Apply settings
        settings.sensitivity = max(5, min(100, optimalSensitivity))
        settings.silenceThreshold = max(5, min(50, optimalSilenceThreshold))
        
        // Min speech: based on longest noise burst (to filter out coughs)
        let optimalMinSpeech = max(0.1, min(0.5, longestNoiseBurst + 0.1))
        settings.minSpeechDuration = optimalMinSpeech
        
        calibrationStep = 3
        calibrationMessage = String(format: "Calibration complete!\nSensitivity: %.0f\nSilence Threshold: %.0f\nMin Speech: %.1fs", 
                                    settings.sensitivity, settings.silenceThreshold, settings.minSpeechDuration)
        
        logger.info("Calibration complete: sensitivity=\(self.settings.sensitivity), silence=\(self.settings.silenceThreshold), minSpeech=\(self.settings.minSpeechDuration)")
        
        // Auto-close after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isCalibrating = false
            self.calibrationStep = 0
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
            playAudio(data: data)
        } catch {
            logger.error("Failed to load audio: \(error.localizedDescription)")
        }
    }
    
    func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            
            isPlaying = true
            status = .speakingZara
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        status = .ready
    }
    
    // MARK: - Fetch and Play from Server
    func playAudio(notification: AudioNotification) {
        let urlString: String
        if let msgId = notification.msgId {
            let chunk = notification.chunk ?? 0
            urlString = "https://agent-flow.net/zara/zara-response?m=\(msgId)&c=\(chunk)"
        } else {
            urlString = "https://agent-flow.net/zara/zara-response?t=\(notification.time)"
        }
        
        guard let url = URL(string: urlString) else {
            logger.error("Invalid audio URL: \(urlString)")
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
                    logger.info("Audio response: \(httpResponse.statusCode), \(data.count) bytes")
                    if httpResponse.statusCode != 200 {
                        logger.error("Audio fetch failed: \(httpResponse.statusCode)")
                        return
                    }
                }
                if data.count < 1000 {
                    logger.warning("Audio too small: \(data.count) bytes")
                    if let text = String(data: data, encoding: .utf8) {
                        logger.warning("Response: \(text)")
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.playAudio(data: data)
                }
            } catch {
                logger.error("Audio fetch error: \(error.localizedDescription)")
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
