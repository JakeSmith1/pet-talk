import CoreGraphics
import CoreVideo
import SpriteKit
import SwiftUI
import Vision

// MARK: - Eye Region Model

/// Detected eye landmarks in Vision normalized coordinates (origin bottom-left, 0...1).
struct EyeRegion: Equatable {
    let leftEyeCenter: CGPoint
    let rightEyeCenter: CGPoint
    let leftEyeRadius: CGFloat
    let rightEyeRadius: CGFloat
    /// Midpoint between the two eyes — useful for eyebrow positioning.
    var midpoint: CGPoint {
        CGPoint(
            x: (leftEyeCenter.x + rightEyeCenter.x) / 2,
            y: (leftEyeCenter.y + rightEyeCenter.y) / 2
        )
    }
}

// MARK: - Eye Animation Keyframe

/// Describes an eye animation state at a given time.
struct EyeKeyframe: Equatable {
    /// 0 = eyes fully open, 1 = eyes fully closed.
    let blinkAmount: Float
    /// 0 = neutral, positive = raised, negative = furrowed.
    let eyebrowRaise: Float
    /// Timestamp in seconds.
    let time: TimeInterval
}

// MARK: - Eye Detection Service

/// Detects eye regions on a pet face using Vision body pose and generates
/// blink/eyebrow keyframes synchronised with audio amplitude.
enum EyeAnimatorService {

    // MARK: - Detection

    /// Attempts to locate the eye region of a pet in the given image.
    ///
    /// Uses `VNDetectAnimalBodyPoseRequest` to find the left-eye and right-eye joints.
    /// Falls back to an estimate based on the nose position if individual eye joints
    /// are unavailable.
    ///
    /// - Parameter image: The source CGImage.
    /// - Returns: An `EyeRegion` in Vision normalized coordinates, or `nil` if detection fails.
    static func detectEyeRegion(in image: CGImage) async -> EyeRegion? {
        let request = VNDetectAnimalBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image)

        do {
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
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }

        // Try dedicated eye joints first.
        if let leftEye = try? observation.recognizedPoint(.leftEye),
           let rightEye = try? observation.recognizedPoint(.rightEye),
           leftEye.confidence > 0.1,
           rightEye.confidence > 0.1 {
            let interEyeDistance = hypot(
                rightEye.location.x - leftEye.location.x,
                rightEye.location.y - leftEye.location.y
            )
            let radius = max(interEyeDistance * 0.25, 0.03)
            return EyeRegion(
                leftEyeCenter: leftEye.location,
                rightEyeCenter: rightEye.location,
                leftEyeRadius: radius,
                rightEyeRadius: radius
            )
        }

        // Fallback: estimate from nose.
        if let nose = try? observation.recognizedPoint(.nose), nose.confidence > 0.1 {
            let offset: CGFloat = 0.08
            let spread: CGFloat = 0.06
            let radius: CGFloat = 0.03
            let leftCenter = CGPoint(x: nose.location.x - spread, y: nose.location.y + offset)
            let rightCenter = CGPoint(x: nose.location.x + spread, y: nose.location.y + offset)
            return EyeRegion(
                leftEyeCenter: leftCenter,
                rightEyeCenter: rightCenter,
                leftEyeRadius: radius,
                rightEyeRadius: radius
            )
        }

        return nil
    }

    // MARK: - Keyframe Generation

    /// Generates eye animation keyframes from audio amplitudes.
    ///
    /// Blinks are triggered stochastically at moments of low amplitude, and eyebrow
    /// raises are driven by amplitude peaks.
    ///
    /// - Parameters:
    ///   - amplitudes: Per-frame amplitude values (0...1) at the given fps.
    ///   - fps: Frame rate of the amplitude data.
    /// - Returns: One `EyeKeyframe` per frame.
    static func generateKeyframes(amplitudes: [Float], fps: Double = 30) -> [EyeKeyframe] {
        guard !amplitudes.isEmpty else { return [] }

        var keyframes: [EyeKeyframe] = []
        keyframes.reserveCapacity(amplitudes.count)

        let blinkDurationFrames = Int(fps * 0.15) // ~150ms per blink
        let minBlinkInterval = Int(fps * 2.0)     // at least 2s between blinks
        var framesSinceLastBlink = minBlinkInterval // allow blink right away
        var currentBlinkFrame = 0
        var isBlinking = false

        for (index, amplitude) in amplitudes.enumerated() {
            let time = Double(index) / fps
            var blinkAmount: Float = 0

            // Trigger blinks during quiet moments.
            if !isBlinking && framesSinceLastBlink >= minBlinkInterval && amplitude < 0.15 {
                // Stochastic trigger — ~8% chance per qualifying frame.
                let hash = (index &* 2654435761) & 0xFFFF
                if hash < 0xFFFF / 12 {
                    isBlinking = true
                    currentBlinkFrame = 0
                }
            }

            if isBlinking {
                // Triangle blink shape: ramp up then down.
                let halfBlink = blinkDurationFrames / 2
                if currentBlinkFrame <= halfBlink {
                    blinkAmount = Float(currentBlinkFrame) / Float(max(halfBlink, 1))
                } else {
                    let remaining = blinkDurationFrames - currentBlinkFrame
                    blinkAmount = Float(remaining) / Float(max(halfBlink, 1))
                }
                currentBlinkFrame += 1
                if currentBlinkFrame >= blinkDurationFrames {
                    isBlinking = false
                    framesSinceLastBlink = 0
                }
            }

            framesSinceLastBlink += 1

            // Eyebrow raise proportional to amplitude (with a slight exaggeration).
            let eyebrowRaise = min(amplitude * 1.5, 1.0)

            keyframes.append(EyeKeyframe(
                blinkAmount: blinkAmount,
                eyebrowRaise: eyebrowRaise,
                time: time
            ))
        }

        return keyframes
    }
}
