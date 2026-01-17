import SwiftUI

struct VoiceView: View {
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var sseClient = SSEClient.shared
    @State private var transcribedText = ""
    @State private var logs: [String] = []
    
    // Video watch mode
    @State private var showingVideoWatch = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.18)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Status indicator
                    statusBadge

                    // Audio level meter
                    audioLevelMeter

                    // Transcript area
                    transcriptArea

                    Spacer()

                    // Main control button
                    mainButton
                    
                    // Auto-send toggle
                    Toggle(isOn: $audioManager.autoSendEnabled) {
                        Text("Auto-send on silence")
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    .padding(.horizontal, 40)

                    // Secondary buttons
                    secondaryButtons
                }
                .padding()
            }
            .navigationTitle("Zara Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.1, green: 0.1, blue: 0.18), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .fullScreenCover(isPresented: $showingVideoWatch) {
                VideoWatchView()
            }
        }
        .onAppear {
            sseClient.connect()
            // Set up chunk ready callback for continuous mode
            audioManager.onChunkReady = { [self] audioData in
                sendChunk(audioData)
            }
        }
        .onChange(of: sseClient.latestNotification) { _, notification in
            if let notification = notification {
                audioManager.playAudio(notification: notification)
                if let text = notification.text {
                    addLog("Zara: \(text)")
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack {
            Text(audioManager.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(statusColor)
                .foregroundColor(.white)
                .cornerRadius(20)
            
            if audioManager.isRecording && audioManager.autoSendEnabled {
                Text(String(format: "%.0f", audioManager.normalizedLevel))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }

    private var statusColor: Color {
        switch audioManager.status {
        case .ready: return Color(red: 0.17, green: 0.17, blue: 0.3)
        case .listening: return Color(red: 0.12, green: 0.23, blue: 0.12)
        case .speaking: return Color(red: 0.12, green: 0.35, blue: 0.12)
        case .silenceDetected: return Color(red: 0.23, green: 0.23, blue: 0.12)
        case .sending: return Color(red: 0.12, green: 0.12, blue: 0.23)
        case .speakingZara: return Color(red: 0.23, green: 0.12, blue: 0.12)
        case .paused: return Color(red: 0.23, green: 0.23, blue: 0.12)
        }
    }

    private var audioLevelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.2))

                RoundedRectangle(cornerRadius: 5)
                    .fill(audioManager.isSpeaking ? Color.green : Color.purple)
                    .frame(width: geometry.size.width * CGFloat(audioManager.audioLevel))
            }
        }
        .frame(height: 10)
    }

    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(logs.indices, id: \.self) { index in
                    Text(logs[index])
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding()
        .background(Color(red: 0.17, green: 0.17, blue: 0.3))
        .cornerRadius(10)
    }

    private var mainButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 100, height: 100)

                if audioManager.isListening {
                    // Stop icon
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                } else {
                    // Mic icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
        }
        .scaleEffect(audioManager.isSpeaking ? 1.15 : (audioManager.isListening ? 1.05 : 1.0))
        .animation(.easeInOut(duration: 0.2), value: audioManager.isListening)
        .animation(.easeInOut(duration: 0.1), value: audioManager.isSpeaking)
    }
    
    private var buttonColor: Color {
        if audioManager.isSpeaking {
            return .green
        } else if audioManager.isRecording {
            return Color(red: 0.2, green: 0.5, blue: 0.2)
        } else {
            return .purple
        }
    }

    private var secondaryButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                // Camera button
                Button(action: captureCamera) {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.3))
                        .foregroundColor(.cyan)
                        .cornerRadius(8)
                }

                // Screenshot button
                Button(action: captureScreen) {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.3))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }

                // Debug button
                Button(action: sendDebug) {
                    Label("Debug", systemImage: "ladybug.fill")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.3))
                        .foregroundColor(.yellow)
                        .cornerRadius(8)
                }
            }
            
            // Video Watch button - opens full screen camera
            Button(action: { showingVideoWatch = true }) {
                Label("Video Watch", systemImage: "video.fill")
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.3))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            }
        }
    }

    private func toggleRecording() {
        if audioManager.isListening {
            // Stop listening - this will send final chunk if needed
            audioManager.stopListening()
            addLog("Listening stopped")
        } else {
            audioManager.startListening()
            addLog("Listening started...")
        }
    }

    // Called by AudioManager when auto-send triggers (continuous mode)
    private func sendChunk(_ audioData: Data) {
        addLog("Auto-sending chunk...")

        Task {
            do {
                let response = try await APIService.shared.transcribe(audioData: audioData)

                // Check if response was filtered (noise, hallucination, speaker mismatch)
                if response.wasFiltered {
                    DispatchQueue.main.async {
                        let reason = response.filtered ?? "unknown"
                        let confStr = response.confidence.map { " [\($0)]" } ?? ""
                        self.addLog("Filtered: \(reason)\(confStr)")
                    }
                    return
                }

                // Get the final transcription text
                if let text = response.text ?? response.whisperText {
                    DispatchQueue.main.async {
                        self.transcribedText = text

                        // Show confidence and speaker info if available
                        var details = ""
                        if let conf = response.confidence {
                            details += " [\(conf)]"
                        }
                        if let sim = response.similarity {
                            details += String(format: " [emb:%.2f]", sim)
                        }

                        self.addLog("You: \(text)\(details)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.addLog("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // Manual stop and send (for when user taps button to stop)
    private func stopAndSend() {
        guard let audioData = audioManager.stopRecording() else {
            addLog("Failed to get recording data")
            return
        }

        addLog("Sending final audio...")
        sendChunk(audioData)
    }

    private func captureCamera() {
        Task {
            do {
                try await CameraManager.shared.uploadCameraPhoto()
                addLog("Camera photo shared!")
            } catch {
                addLog("Camera error: \(error.localizedDescription)")
            }
        }
    }

    private func captureScreen() {
        Task {
            do {
                try await CameraManager.shared.uploadScreenshot()
                addLog("Screenshot shared!")
            } catch {
                addLog("Screenshot error: \(error.localizedDescription)")
            }
        }
    }

    private func sendDebug() {
        Task {
            do {
                guard let screenshot = CameraManager.shared.takeScreenshot(),
                      let imageData = screenshot.pngData() else {
                    addLog("Failed to capture debug screenshot")
                    return
                }

                _ = try await APIService.shared.uploadDebugScreenshot(
                    imageData: imageData,
                    logs: logs,
                    elements: []
                )
                addLog("Debug info sent!")
            } catch {
                addLog("Debug error: \(error.localizedDescription)")
            }
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("\(timestamp): \(message)", at: 0)
        if logs.count > 50 {
            logs.removeLast()
        }
    }
}

#Preview {
    VoiceView()
}
