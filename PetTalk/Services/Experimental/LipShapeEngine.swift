import Foundation

// MARK: - MouthShape

/// Represents a viseme — the visual equivalent of a phoneme.
/// Each case maps to a distinct mouth pose used for realistic lip-sync animation.
enum MouthShape: String, CaseIterable, Identifiable {
    /// Mouth closed / resting position (M, B, P sounds).
    case closed
    /// Slightly open, neutral (schwa / unstressed vowels).
    case neutral
    /// Wide open (AH, AA sounds).
    case open
    /// Wide / stretched horizontally (EE, IH sounds).
    case wide
    /// Rounded / puckered (OO, UW sounds).
    case rounded
    /// Lower lip tucked under teeth (F, V sounds).
    case lipBite
    /// Tongue visible between teeth (TH sounds).
    case tongueOut
    /// Teeth together, slight grimace (S, Z, SH sounds).
    case clenched

    var id: String { rawValue }

    /// A human-readable label for display in debug or experimental UI.
    var displayName: String {
        switch self {
        case .closed:    return "Closed"
        case .neutral:   return "Neutral"
        case .open:      return "Open"
        case .wide:      return "Wide"
        case .rounded:   return "Rounded"
        case .lipBite:   return "Lip Bite"
        case .tongueOut: return "Tongue Out"
        case .clenched:  return "Clenched"
        }
    }
}

// MARK: - ShapeParameters

/// Describes how to deform the mouth mesh for a given viseme.
struct ShapeParameters: Equatable {
    /// Vertical jaw opening in normalized range 0...1.
    let jawOpen: Float
    /// Horizontal lip stretch in range -1...1 (negative = pucker, positive = smile).
    let lipStretch: Float
    /// Upper lip raise in 0...1.
    let upperLipRaise: Float
    /// Lower lip depression in 0...1.
    let lowerLipDrop: Float

    /// A resting / fully closed mouth.
    static let rest = ShapeParameters(jawOpen: 0, lipStretch: 0, upperLipRaise: 0, lowerLipDrop: 0)
}

// MARK: - PhonemeKeyframe

/// A single keyframe in a phoneme-driven animation timeline.
struct PhonemeKeyframe: Identifiable {
    let id = UUID()
    /// Time offset in seconds from the start of the audio clip.
    let time: TimeInterval
    /// The target mouth shape at this keyframe.
    let shape: MouthShape
    /// The deformation parameters for blending.
    let parameters: ShapeParameters
    /// Confidence score from the phoneme recognition pass (0...1).
    let confidence: Float
}

// MARK: - LipShapeEngine

/// Stub service for phoneme-to-viseme lip-shape analysis.
///
/// When the Lip-Shape Matching experiment is enabled, this engine replaces the
/// simple amplitude-based mouth animation with a phoneme-aware keyframe timeline.
///
/// **Current status: Concept** -- all methods return placeholder data.
final class LipShapeEngine {

    /// Maps a `MouthShape` to its canonical deformation parameters.
    static func parameters(for shape: MouthShape) -> ShapeParameters {
        switch shape {
        case .closed:
            return .rest
        case .neutral:
            return ShapeParameters(jawOpen: 0.15, lipStretch: 0.0, upperLipRaise: 0.05, lowerLipDrop: 0.1)
        case .open:
            return ShapeParameters(jawOpen: 0.85, lipStretch: 0.1, upperLipRaise: 0.3, lowerLipDrop: 0.7)
        case .wide:
            return ShapeParameters(jawOpen: 0.35, lipStretch: 0.7, upperLipRaise: 0.15, lowerLipDrop: 0.2)
        case .rounded:
            return ShapeParameters(jawOpen: 0.45, lipStretch: -0.6, upperLipRaise: 0.1, lowerLipDrop: 0.3)
        case .lipBite:
            return ShapeParameters(jawOpen: 0.1, lipStretch: 0.0, upperLipRaise: 0.0, lowerLipDrop: 0.05)
        case .tongueOut:
            return ShapeParameters(jawOpen: 0.3, lipStretch: 0.0, upperLipRaise: 0.1, lowerLipDrop: 0.2)
        case .clenched:
            return ShapeParameters(jawOpen: 0.05, lipStretch: 0.4, upperLipRaise: 0.0, lowerLipDrop: 0.0)
        }
    }

    /// Analyzes the audio file and produces a timeline of phoneme keyframes.
    ///
    /// - Parameters:
    ///   - audioURL: URL to the audio file.
    ///   - fps: Target keyframe rate.
    /// - Returns: An ordered array of `PhonemeKeyframe` values.
    ///
    /// > Important: This is a **stub** implementation. It generates synthetic
    /// > keyframes cycling through shapes for demonstration purposes only.
    func analyzePhonemes(audioURL: URL, fps: Double = 30) async throws -> [PhonemeKeyframe] {
        // Stub: generate placeholder keyframes over an estimated 5-second duration.
        let estimatedDuration: TimeInterval = 5.0
        let frameCount = Int(estimatedDuration * fps)
        let shapes = MouthShape.allCases

        return (0..<frameCount).map { frame in
            let time = Double(frame) / fps
            let shape = shapes[frame % shapes.count]
            return PhonemeKeyframe(
                time: time,
                shape: shape,
                parameters: Self.parameters(for: shape),
                confidence: Float.random(in: 0.6...1.0)
            )
        }
    }

    /// Interpolates between two sets of `ShapeParameters` for smooth blending.
    ///
    /// - Parameters:
    ///   - from: Starting parameters.
    ///   - to: Target parameters.
    ///   - progress: Blend factor in 0...1.
    /// - Returns: The interpolated parameters.
    static func interpolate(from: ShapeParameters, to: ShapeParameters, progress: Float) -> ShapeParameters {
        let t = min(max(progress, 0), 1)
        return ShapeParameters(
            jawOpen:       from.jawOpen       + (to.jawOpen       - from.jawOpen)       * t,
            lipStretch:    from.lipStretch    + (to.lipStretch    - from.lipStretch)    * t,
            upperLipRaise: from.upperLipRaise + (to.upperLipRaise - from.upperLipRaise) * t,
            lowerLipDrop:  from.lowerLipDrop  + (to.lowerLipDrop  - from.lowerLipDrop)  * t
        )
    }
}
