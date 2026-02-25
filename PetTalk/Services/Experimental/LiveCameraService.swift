import AVFoundation
import Combine
import CoreImage
import UIKit
import Vision

// MARK: - LiveCameraState

/// Observable state published by `LiveCameraService` for the UI layer.
enum LiveCameraState: Equatable {
    case idle
    case starting
    case running
    case stopped
    case error(String)
}

// MARK: - LiveCameraService

/// Stub service that manages an AVCaptureSession + Vision pipeline for live
/// pet-mouth AR overlay.
///
/// **Current status: Prototype** -- the capture session setup is realistic but
/// the Vision processing pipeline returns placeholder data. No actual AR overlay
/// compositing is performed yet.
@MainActor
final class LiveCameraService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: LiveCameraState = .idle

    /// The latest camera frame as a UIImage (for preview display).
    @Published var currentFrame: UIImage?

    /// The detected mouth region from the Vision pipeline, if any.
    @Published var detectedMouthRegion: MouthRegion?

    /// Frames-per-second measurement for the debug overlay.
    @Published var currentFPS: Double = 0

    // MARK: - Capture Session

    /// The underlying capture session. Configured but not started until
    /// `startSession()` is called.
    let captureSession = AVCaptureSession()

    private var videoOutput: AVCaptureVideoDataOutput?
    private let processingQueue = DispatchQueue(label: "com.pettalk.livecamera", qos: .userInteractive)

    // MARK: - FPS Tracking

    private var frameTimestamps: [CFTimeInterval] = []

    // MARK: - Session Lifecycle

    /// Configures and starts the capture session with the rear camera.
    ///
    /// > Note: On simulator or when no camera is available, the service transitions
    /// > to the `.error` state gracefully.
    func startSession() {
        guard state != .running else { return }
        state = .starting

        // Stub: In a real implementation this would configure the AVCaptureSession
        // with a camera device input and a video data output, then start running.
        //
        // captureSession.beginConfiguration()
        // ... add inputs / outputs ...
        // captureSession.commitConfiguration()
        // captureSession.startRunning()

        // For now, simulate a brief startup delay and transition to running.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s simulated startup
            state = .running
        }
    }

    /// Stops the capture session and releases resources.
    func stopSession() {
        // captureSession.stopRunning()
        currentFrame = nil
        detectedMouthRegion = nil
        currentFPS = 0
        frameTimestamps.removeAll()
        state = .stopped
    }

    // MARK: - Vision Pipeline (Stub)

    /// Processes a sample buffer through the Vision animal-pose pipeline.
    ///
    /// In production, this would:
    /// 1. Create a `VNImageRequestHandler` from the pixel buffer.
    /// 2. Perform a `VNDetectAnimalBodyPoseRequest`.
    /// 3. Extract the nose joint and estimate the mouth region.
    /// 4. Publish the detected region for AR overlay compositing.
    ///
    /// Currently returns placeholder data.
    nonisolated func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // Stub: Real implementation would run Vision requests here.
        //
        // guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        // let request = VNDetectAnimalBodyPoseRequest()
        // try? handler.perform([request])
        // ...

        let now = CACurrentMediaTime()

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Simulated FPS tracking
            self.frameTimestamps.append(now)
            self.frameTimestamps = self.frameTimestamps.filter { now - $0 < 1.0 }
            self.currentFPS = Double(self.frameTimestamps.count)

            // Simulated detection result
            self.detectedMouthRegion = MouthRegion(
                center: CGPoint(x: 0.5, y: 0.35),
                radius: 0.08
            )
        }
    }

    // MARK: - Camera Permission

    /// Checks whether the app has camera access.
    static func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LiveCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processFrame(sampleBuffer)
    }
}
