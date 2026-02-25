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

        // Collect all confident head joints (nose + ears) to locate the head.
        let nosePoint = try? firstResult.recognizedPoint(.nose)
        let leftEar = try? firstResult.recognizedPoint(.leftEarMiddle)
        let rightEar = try? firstResult.recognizedPoint(.rightEarMiddle)

        let confidentNose = nosePoint.flatMap { $0.confidence > 0.3 ? $0 : nil }
        let confidentLeftEar = leftEar.flatMap { $0.confidence > 0.3 ? $0 : nil }
        let confidentRightEar = rightEar.flatMap { $0.confidence > 0.3 ? $0 : nil }

        // Strategy 1: High-confidence nose, validated against ears when available.
        if let nose = confidentNose {
            // If we also have an ear, verify the nose is near the head (not a misdetected limb).
            if let ear = confidentLeftEar ?? confidentRightEar {
                let dist = hypot(nose.location.x - ear.location.x, nose.location.y - ear.location.y)
                // Nose and ear should be within ~30% of image size of each other.
                if dist > 0.3 {
                    throw PetDetectionError.noPoseDetected
                }
            }

            let mouthCenter = CGPoint(
                x: nose.location.x,
                y: nose.location.y - noseToMouthOffset
            ).clamped()
            return MouthRegion(center: mouthCenter, radius: defaultMouthRadius)
        }

        // Strategy 2: No confident nose, but we have ear(s) — estimate mouth from ear midpoint.
        let ears = [confidentLeftEar, confidentRightEar].compactMap { $0 }
        if !ears.isEmpty {
            let earCenterX = ears.map { $0.location.x }.reduce(0, +) / CGFloat(ears.count)
            let earCenterY = ears.map { $0.location.y }.reduce(0, +) / CGFloat(ears.count)

            // Mouth is below and roughly centered between the ears.
            let mouthCenter = CGPoint(
                x: earCenterX,
                y: earCenterY - noseToMouthOffset * 2
            ).clamped()
            return MouthRegion(center: mouthCenter, radius: defaultMouthRadius)
        }

        throw PetDetectionError.noPoseDetected
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

        // Place the mouth at the horizontal center, roughly 65% up from the bottom of the
        // bounding box (upper portion where the head typically is for standing/sitting pets).
        let mouthCenter = CGPoint(
            x: box.midX,
            y: box.minY + box.height * 0.65
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
