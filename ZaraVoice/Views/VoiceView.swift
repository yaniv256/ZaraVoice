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
        }
        .onChange(of: sseClient.latestNotification) { _, notification in
            if let notification = notification {
                audioManager.playLatestAudio(timestamp: notification.time)
                if let text = notification.text {
                    addLog("Zara: \(text)")
                }
            }
        }
        .onDisappear {
            stopVideoWatch()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Text(audioManager.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(statusColor)
                .foregroundColor(.white)
                .cornerRadius(20)
            
            if isVideoWatching {
                Text("📹 \(Int(captureInterval))s")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.3))
                    .foregroundColor(.red)
                    .cornerRadius(20)
            }
        }
    }

    private var statusColor: Color {
        switch audioManager.status {
        case .ready: return Color(red: 0.17, green: 0.17, blue: 0.3)
        case .listening: return Color(red: 0.12, green: 0.23, blue: 0.12)
        case .sending: return Color(red: 0.12, green: 0.12, blue: 0.23)
        case .speaking: return Color(red: 0.23, green: 0.12, blue: 0.12)
        case .paused: return Color(red: 0.23, green: 0.23, blue: 0.12)
        }
    }

    private var audioLevelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.2))

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.purple)
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
                    .fill(audioManager.isRecording ? Color.green : Color.purple)
                    .frame(width: 100, height: 100)

                if audioManager.isRecording {
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
        .scaleEffect(audioManager.isRecording ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: audioManager.isRecording)
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
        if audioManager.isRecording {
            stopAndSend()
        } else {
            audioManager.startRecording()
            addLog("Recording started...")
        }
    }

    private func stopAndSend() {
        guard let audioData = audioManager.stopRecording() else {
            addLog("Failed to get recording data")
            return
        }

        addLog("Sending audio...")

        Task {
            do {
                let response = try await APIService.shared.transcribe(audioData: audioData)
                if let text = response.text ?? response.whisperText {
                    DispatchQueue.main.async {
                        self.transcribedText = text
                        self.addLog("You: \(text)")
                    }
                    // Push to session
                    try await APIService.shared.pushToSession(role: "user", content: text)
                }
                DispatchQueue.main.async {
                    audioManager.status = .ready
                }
            } catch {
                DispatchQueue.main.async {
                    self.addLog("Error: \(error.localizedDescription)")
                    audioManager.status = .ready
                }
            }
        }
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
