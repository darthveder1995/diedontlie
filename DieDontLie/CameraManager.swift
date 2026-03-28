import AVFoundation
import CoreVideo
import UIKit

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation)
}

final class CameraManager: NSObject {

    weak var delegate: CameraManagerDelegate?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.diedontlie.camera.session")
    private let outputQueue = DispatchQueue(label: "com.diedontlie.camera.output")

    // Expose session so the preview layer can attach to it
    var captureSession: AVCaptureSession { session }

    // MARK: - Setup

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configure() }
            }
        default:
            break
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Private

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)

            self.videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            // Lock to landscape-right so coordinates stay consistent
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoRotationAngle = 0
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraManager(self, didOutput: pixelBuffer, orientation: .right)
    }
}
