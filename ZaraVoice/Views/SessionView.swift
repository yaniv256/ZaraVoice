import SwiftUI
import AVFoundation

struct SessionView: View {
    @State private var messages: [SessionMessage] = []
    @State private var isLoading = false
    @State private var inputText = ""
    @State private var currentlyPlayingId: UUID?
    @State private var audioPlayer: AVPlayer?

    private let baseURL = "https://agent-flow.net/zara"

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.18)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Messages list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubble(
                                        message: message,
                                        isPlaying: currentlyPlayingId == message.id,
                                        onPlayTap: { playAudio(for: message) }
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    // Input area
                    inputArea
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.1, green: 0.1, blue: 0.18), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: refreshHistory) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            refreshHistory()
        }
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.17, green: 0.17, blue: 0.3))
                .foregroundColor(.white)
                .cornerRadius(25)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(red: 0.12, green: 0.12, blue: 0.2))
    }

    private func refreshHistory() {
        isLoading = true
        Task {
            do {
                let history = try await APIService.shared.getSessionHistory()
                DispatchQueue.main.async {
                    self.messages = history
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let newMessage = SessionMessage(role: "user", content: content)
        messages.append(newMessage)
        inputText = ""

        Task {
            do {
                try await APIService.shared.pushToSession(role: "user", content: content)
            } catch {
                print("Failed to push message: \(error)")
            }
        }
    }

    private func playAudio(for message: SessionMessage) {
        // If same message is playing, stop it
        if currentlyPlayingId == message.id {
            audioPlayer?.pause()
            currentlyPlayingId = nil
            return
        }

        // Stop any current playback
        audioPlayer?.pause()

        guard let url = message.getAudioURL(baseURL: baseURL) else {
            print("No audio URL for message")
            return
        }

        // Download audio with authentication, then play from local file
        var request = URLRequest(url: url)
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        currentlyPlayingId = message.id  // Show loading state

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Failed to download audio: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    DispatchQueue.main.async { self.currentlyPlayingId = nil }
                    return
                }

                // Save to temp file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp3")
                try data.write(to: tempURL)

                // Play from local file on main thread
                DispatchQueue.main.async {
                    let playerItem = AVPlayerItem(url: tempURL)
                    self.audioPlayer = AVPlayer(playerItem: playerItem)

                    // Observe when playback ends
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main
                    ) { _ in
                        self.currentlyPlayingId = nil
                        // Clean up temp file
                        try? FileManager.default.removeItem(at: tempURL)
                    }

                    self.audioPlayer?.play()
                }
            } catch {
                print("Error downloading audio: \(error)")
                DispatchQueue.main.async { self.currentlyPlayingId = nil }
            }
        }
    }
}

struct MessageBubble: View {
    let message: SessionMessage
    let isPlaying: Bool
    let onPlayTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Header row with role, time, and play button
                HStack(spacing: 6) {
                    // Play button (if has audio)
                    if message.hasAudio {
                        Button(action: onPlayTap) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(message.isUser ? .purple : .blue)
                        }
                    }

                    // Role label with emoji for voice messages
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundColor(.gray)

                    // Time if available
                    if let time = message.time {
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }

                // Message content
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(bubbleColor)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }

            if !message.isUser { Spacer() }
        }
    }

    private var roleLabel: String {
        if message.isUser { return "You" }
        if message.isZaraVoice { return "🎤 Zara" }
        return "Zara"
    }

    private var bubbleColor: Color {
        if message.isUser {
            return Color.purple.opacity(0.3)
        }
        return Color(red: 0.12, green: 0.23, blue: 0.37)
    }
}

#Preview {
    SessionView()
}
