import AVFoundation
import UIKit

// MARK: - UIImage Orientation Fix
extension UIImage {
    /// Returns a new image with normalized orientation (up)
    /// Uses explicit CGContext transforms to properly rotate the image
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        guard let cgImage = self.cgImage else { return self }
        
        var transform = CGAffineTransform.identity
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        // Determine the correct output size and transform based on orientation
        let outputWidth: CGFloat
        let outputHeight: CGFloat
        
        switch imageOrientation {
        case .down, .downMirrored:
            outputWidth = width
            outputHeight = height
            transform = transform.translatedBy(x: width, y: height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: height, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: 0, y: width)
            transform = transform.rotated(by: -.pi / 2)
        default:
            outputWidth = width
            outputHeight = height
        }
        
        // Handle mirroring
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        // Create context with correct size
        guard let context = CGContext(
            data: nil,
            width: Int(outputWidth),
            height: Int(outputHeight),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return self
        }
        
        context.concatenate(transform)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let newCGImage = context.makeImage() else { return self }
        return UIImage(cgImage: newCGImage, scale: scale, orientation: .up)
    }
}

class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var isCameraAvailable = false
    @Published var capturedImage: UIImage?
    @Published var isSessionRunning = false

    private(set) var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
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
        }

        guard let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            print("[CameraManager] Failed to get image data from photo")
            photoContinuation?.resume(returning: nil)
            photoContinuation = nil
            return
        }

        let image = rawImage.normalizedOrientation()
        print("[CameraManager] Photo captured - orientation: \(rawImage.imageOrientation.rawValue), raw: \(rawImage.size), normalized: \(image.size)")

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
