import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var isCameraAvailable = false
    @Published var capturedImage: UIImage?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    override private init() {
        super.init()
        checkCameraAvailability()
    }

    private func checkCameraAvailability() {
        isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func setupCamera() {
        guard isCameraAvailable else { return }

        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
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

    func capturePhoto() async -> UIImage? {
        guard let photoOutput = photoOutput else {
            // Fallback: use UIImagePickerController approach
            return nil
        }

        // Start session if needed
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
            // Wait for session to start
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
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
        guard let image = await capturePhoto(),
              let imageData = image.pngData() else {
            throw CameraError.captureFailed
        }

        _ = try await APIService.shared.uploadScreenshot(
            imageData: imageData,
            type: "camera",
            source: "ios-app-camera"
        )
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            photoContinuation?.resume(returning: nil)
            photoContinuation = nil
            return
        }

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
