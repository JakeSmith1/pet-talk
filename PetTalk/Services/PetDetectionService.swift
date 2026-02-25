import CoreGraphics
import Vision

// MARK: - Errors

/// Errors that can occur during pet detection.
enum PetDetectionError: LocalizedError {
    case noAnimalDetected
    case noPoseDetected
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .noAnimalDetected:
            return "No cat or dog was detected in the image."
        case .noPoseDetected:
            return "Could not detect the animal's pose."
        case .imageConversionFailed:
            return "Failed to process the image."
        }
    }
}

// MARK: - Service

/// Detects the mouth region of a pet (cat or dog) in an image using the Vision framework.
enum PetDetectionService {

    /// The vertical offset from the nose to estimate the mouth center, expressed as a
    /// fraction of image height in normalized Vision coordinates (origin at bottom-left).
    private static let noseToMouthOffset: CGFloat = 0.15

    /// Default mouth radius in normalized coordinates.
    private static let defaultMouthRadius: CGFloat = 0.08

    // MARK: - Public API

    /// Detects the mouth region of a pet in the given image.
    ///
    /// Uses `VNDetectAnimalBodyPoseRequest` (iOS 17+) as the primary strategy and falls
    /// back to `VNRecognizeAnimalsRequest` bounding-box estimation when pose detection
    /// does not yield a usable nose joint.
    ///
    /// - Parameter image: The source image to analyze.
    /// - Returns: A ``MouthRegion`` with center and radius in normalized 0...1 coordinates.
    /// - Throws: ``PetDetectionError`` if no animal or pose can be detected.
    static func detectMouthRegion(in image: CGImage) async throws -> MouthRegion {
        // Try body-pose detection first.
        if let region = try? await detectMouthUsingBodyPose(in: image) {
            return region
        }

        // Fallback: bounding-box based estimation.
        return try await detectMouthUsingBoundingBox(in: image)
    }

    // MARK: - Body Pose Strategy

    private static func detectMouthUsingBodyPose(in image: CGImage) async throws -> MouthRegion {
        let request = VNDetectAnimalBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image)

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let firstResult = request.results?.first else {
            throw PetDetectionError.noPoseDetected
        }

        // Attempt to extract the nose joint from the head group.
        let nosePoint = try firstResult.recognizedPoint(.nose)

        guard nosePoint.confidence > 0.1 else {
            throw PetDetectionError.noPoseDetected
        }

        // Vision coordinates have origin at bottom-left; moving "down" toward the mouth
        // means *decreasing* y.
        let mouthCenter = CGPoint(
            x: nosePoint.location.x,
            y: nosePoint.location.y - noseToMouthOffset
        ).clamped()

        return MouthRegion(center: mouthCenter, radius: defaultMouthRadius)
    }

    // MARK: - Bounding Box Fallback

    private static func detectMouthUsingBoundingBox(in image: CGImage) async throws -> MouthRegion {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: image)

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let firstResult = request.results?.first else {
            throw PetDetectionError.noAnimalDetected
        }

        let box = firstResult.boundingBox

        // Place the mouth at the horizontal center, roughly 20% up from the bottom of the
        // bounding box (lower-center of the face).
        let mouthCenter = CGPoint(
            x: box.midX,
            y: box.minY + box.height * 0.20
        ).clamped()

        let radius = min(box.width, box.height) * 0.15

        return MouthRegion(center: mouthCenter, radius: radius)
    }
}

// MARK: - Helpers

private extension CGPoint {
    /// Clamps both coordinates to the 0...1 range.
    func clamped() -> CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}
