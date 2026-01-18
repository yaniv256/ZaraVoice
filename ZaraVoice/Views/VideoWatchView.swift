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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen camera preview with pinch-to-zoom
                CameraPreviewView(session: cameraManager.captureSession, photoOutput: cameraManager.photoOutput)
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
                        Button(action: { stopAndDismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }

                        Spacer()

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

                        if currentZoom > 1.01 {
                            Text(String(format: "%.1fx", currentZoom))
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                        }

                        Text("\(Int(captureInterval))s")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.5)))

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

                    // Bottom controls
                    HStack(alignment: .center, spacing: 60) {
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
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 60, height: 60)
                        }

                        Button(action: toggleCapture) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 75, height: 75)

                                if isCapturing {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 30, height: 30)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }

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
        }
        .onDisappear {
            stopCapturing()
            cameraManager.stopSession()
        }
        .statusBarHidden(true)
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

        Task {
            try? await APIService.shared.startVideoWatch()
        }

        captureFrame()

        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { _ in
            captureFrame()
        }
    }

    private func stopCapturing() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil

        Task {
            try? await APIService.shared.stopVideoWatch()
        }
    }

    private func captureFrame() {
        Task {
            do {
                let image = try await CameraManager.shared.uploadVideoFrame()
                await MainActor.run {
                    frameCount += 1
                    lastCapturedFrame = image

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
    let photoOutput: AVCapturePhotoOutput?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let session = session {
            uiView.setSession(session, photoOutput: photoOutput)
        }
    }

    class PreviewView: UIView {
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private weak var photoOutput: AVCapturePhotoOutput?
        
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        func setSession(_ session: AVCaptureSession, photoOutput: AVCapturePhotoOutput?) {
            guard videoPreviewLayer.session !== session else { return }

            videoPreviewLayer.session = session
            videoPreviewLayer.videoGravity = .resizeAspectFill
            self.photoOutput = photoOutput
            
            // Set up rotation coordinator for the video device
            if let device = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })?
                .device {
                setupRotationCoordinator(for: device)
            }
        }
        
        private func setupRotationCoordinator(for device: AVCaptureDevice) {
            // Create rotation coordinator - it monitors device orientation
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
            
            // Apply initial rotation
            applyRotation()
            
            // Observe rotation changes
            rotationObservation = rotationCoordinator?.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.applyRotation()
                }
            }
        }
        
        private func applyRotation() {
            guard let coordinator = rotationCoordinator else { return }
            
            // Update preview layer rotation
            if videoPreviewLayer.connection?.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelPreview) == true {
                videoPreviewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            }
            
            // Update photo output connection rotation
            if let photoConnection = photoOutput?.connection(with: .video),
               photoConnection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelCapture) {
                photoConnection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
        }
        
        deinit {
            rotationObservation?.invalidate()
        }
    }
}

#Preview {
    VideoWatchView()
}
