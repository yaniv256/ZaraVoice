import SwiftUI

struct SessionView: View {
    @State private var messages: [SessionMessage] = []
    @State private var isLoading = false
    @State private var inputText = ""

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
                                    MessageBubble(message: message)
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
}

struct MessageBubble: View {
    let message: SessionMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Zara")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? Color.purple.opacity(0.3) : Color(red: 0.12, green: 0.23, blue: 0.37))
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }

            if !message.isUser { Spacer() }
        }
    }
}

#Preview {
    SessionView()
}
