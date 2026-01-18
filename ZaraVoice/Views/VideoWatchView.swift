import SwiftUI
import AVFoundation

struct VideoWatchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager.shared

    @State private var captureInterval: TimeInterval = 30
    @State private var captureTimer: Timer?
    @State private var frameCount = 0
    @State private var isCapturing = false
    @State private var lastCapturedFrame: UIImage?
    @State private var showThumbnail = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back

    // Pinch-to-zoom state
    @State private var currentZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    // Audio player for shutter sound
    @State private var shutterPlayer: AVAudioPlayer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen camera preview with pinch-to-zoom
                CameraPreviewView(session: cameraManager.captureSession)
                    .scaleEffect(currentZoom)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = lastZoom * value
                                currentZoom = min(max(newZoom, 1.0), 5.0)
                            }
                            .onEnded { value in
                                lastZoom = currentZoom
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double-tap to reset zoom
                        withAnimation(.spring(response: 0.3)) {
                            currentZoom = 1.0
                            lastZoom = 1.0
                        }
                    }
                    .ignoresSafeArea()

                // Controls overlay
                VStack {
                    // Top bar
                    HStack {
                        // Close button
                        Button(action: { stopAndDismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }

                        Spacer()

                        // Recording indicator and frame count
                        if isCapturing {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                Text("\(frameCount)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                        }

                        Spacer()

                        // Zoom indicator (only show when zoomed)
                        if currentZoom > 1.01 {
                            Text(String(format: "%.1fx", currentZoom))
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                        }

                        // Interval display
                        Text("\(Int(captureInterval))s")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.5)))

                        // Camera flip button
                        Button(action: flipCamera) {
                            Image(systemName: "camera.rotate")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                    .padding()

                    Spacer()

                    // Bottom controls - camera app style
                    HStack(alignment: .center, spacing: 60) {
                        // Thumbnail of last capture (left side, like camera app)
                        if let lastFrame = lastCapturedFrame {
                            Image(uiImage: lastFrame)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .scaleEffect(showThumbnail ? 1.0 : 0.5)
                                .opacity(showThumbnail ? 1.0 : 0.0)
                                .animation(.spring(response: 0.3), value: showThumbnail)
                        } else {
                            // Placeholder for alignment
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 60, height: 60)
                        }

                        // Main capture/stop button (center)
                        Button(action: toggleCapture) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 75, height: 75)

                                if isCapturing {
                                    // Stop square when recording
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 30, height: 30)
                                } else {
                                    // Record circle when stopped
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }

                        // Interval adjustment (right side)
                        VStack(spacing: 8) {
                            Button(action: { adjustInterval(by: 5) }) {
                                Image(systemName: "plus")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 30)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(6)
                            }

                            Button(action: { adjustInterval(by: -5) }) {
                                Image(systemName: "minus")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 30)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(6)
                            }
                        }
                        .frame(width: 60)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            cameraManager.startSession(position: cameraPosition)
            setupShutterSound()
        }
        .onDisappear {
            stopCapturing()
            cameraManager.stopSession()
        }
        .statusBarHidden(true)
    }

    private func setupShutterSound() {
        // Try to use system shutter sound
        if let soundURL = Bundle.main.url(forResource: "shutter", withExtension: "mp3") {
            shutterPlayer = try? AVAudioPlayer(contentsOf: soundURL)
            shutterPlayer?.prepareToPlay()
        }
    }

    private func playShutterSound() {
        // Play system sound as fallback (camera shutter)
        AudioServicesPlaySystemSound(1108)
    }

    private func toggleCapture() {
        if isCapturing {
            stopCapturing()
        } else {
            startCapturing()
        }
    }

    private func startCapturing() {
        isCapturing = true
        frameCount = 0
        showThumbnail = false

        // Notify EC2
        Task {
            try? await APIService.shared.startVideoWatch()
        }

        // Capture first frame immediately
        captureFrame()

        // Start timer
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { _ in
            captureFrame()
        }
    }

    private func stopCapturing() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil

        // Notify EC2
        Task {
            try? await APIService.shared.stopVideoWatch()
        }
    }

    private func captureFrame() {
        // Shutter sound disabled - interrupts audio playback
        // playShutterSound()

        Task {
            do {
                let image = try await CameraManager.shared.uploadVideoFrame()
                await MainActor.run {
                    frameCount += 1
                    lastCapturedFrame = image

                    // Animate thumbnail appearance
                    withAnimation {
                        showThumbnail = true
                    }
                }
            } catch {
                print("Frame capture error: \(error)")
            }
        }
    }

    private func adjustInterval(by delta: TimeInterval) {
        let newInterval = max(5, min(120, captureInterval + delta))
        if newInterval != captureInterval {
            captureInterval = newInterval

            // Restart timer with new interval if capturing
            if isCapturing {
                captureTimer?.invalidate()
                captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { _ in
                    captureFrame()
                }
            }
        }
    }

    private func stopAndDismiss() {
        stopCapturing()
        dismiss()
    }

    private func flipCamera() {
        cameraPosition = (cameraPosition == .back) ? .front : .back
        cameraManager.stopSession()
        cameraManager.startSession(position: cameraPosition)
    }
}

// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update session when it becomes available
        if let session = session {
            uiView.setSession(session)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
    }

    // Custom UIView that manages its own preview layer
    class PreviewView: UIView {
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        func setSession(_ session: AVCaptureSession) {
            // Only set session if it's different to avoid unnecessary updates
            guard videoPreviewLayer.session !== session else { return }

            videoPreviewLayer.session = session
            videoPreviewLayer.videoGravity = .resizeAspectFill
            // Do NOT set videoRotationAngle here or anywhere - causes error -12784
            // iOS handles preview orientation automatically via the preview layer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Do NOT update orientation here - causes error -12784 during capture
        }
    }
}

#Preview {
    VideoWatchView()
}
