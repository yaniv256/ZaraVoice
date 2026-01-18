import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var isCameraAvailable = false
    @Published var capturedImage: UIImage?
    @Published var isSessionRunning = false

    private(set) var captureSession: AVCaptureSession?
    // Expose photoOutput so VideoWatchView can set rotation on its connection
    private(set) var photoOutput: AVCapturePhotoOutput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    override private init() {
        super.init()
        checkCameraAvailability()
    }

    private func checkCameraAvailability() {
        isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func setupCamera(position: AVCaptureDevice.Position = .front, forceReset: Bool = false) {
        guard isCameraAvailable else { return }

        if captureSession != nil && currentCameraPosition == position && !forceReset {
            return
        }

        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        currentCameraPosition = position

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        if captureSession?.canAddInput(input) == true {
            captureSession?.addInput(input)
        }

        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession?.canAddOutput(photoOutput) == true {
            captureSession?.addOutput(photoOutput)
        }
    }

    func startSession(position: AVCaptureDevice.Position = .back) {
        let needsReset = currentCameraPosition != position
        setupCamera(position: position, forceReset: needsReset)
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func capturePhoto(position: AVCaptureDevice.Position = .front) async -> UIImage? {
        setupCamera(position: position)

        guard let photoOutput = photoOutput else {
            print("[CameraManager] photoOutput is nil")
            return nil
        }

        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Do NOT set videoRotationAngle here - it's set by RotationCoordinator in VideoWatchView

        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            print("[CameraManager] Capturing photo...")
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func takeScreenshot() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    func uploadScreenshot() async throws {
        guard let image = takeScreenshot(),
              let imageData = image.pngData() else {
            throw CameraError.captureFailed
        }

        _ = try await APIService.shared.uploadScreenshot(
            imageData: imageData,
            type: "screen",
            source: "ios-app"
        )
    }

    func uploadCameraPhoto() async throws {
        guard let image = await capturePhoto(position: .front),
              let imageData = image.pngData() else {
            throw CameraError.captureFailed
        }

        _ = try await APIService.shared.uploadScreenshot(
            imageData: imageData,
            type: "camera",
            source: "ios-app-camera"
        )
    }

    func uploadVideoFrame() async throws -> UIImage {
        guard let image = await capturePhoto(position: .back),
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw CameraError.captureFailed
        }

        _ = try await APIService.shared.uploadVideoFrame(imageData: imageData)
        return image
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[CameraManager] Photo capture error: \(error)")
            photoContinuation?.resume(returning: nil)
            photoContinuation = nil
            return
        }

        // The rotation is already set on the connection by RotationCoordinator,
        // so fileDataRepresentation includes correct orientation
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("[CameraManager] Failed to get image data")
            photoContinuation?.resume(returning: nil)
            photoContinuation = nil
            return
        }

        print("[CameraManager] Photo captured - size: \(image.size), orientation: \(image.imageOrientation.rawValue)")

        DispatchQueue.main.async {
            self.capturedImage = image
        }
        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

enum CameraError: Error {
    case captureFailed
    case uploadFailed
}
