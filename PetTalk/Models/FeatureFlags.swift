import Foundation
import SwiftUI

// MARK: - Experiment Status

/// The maturity level of an experimental feature.
enum ExperimentStatus: String, Codable, CaseIterable {
    case concept
    case prototype
    case beta

    var label: String {
        switch self {
        case .concept:   return "Concept"
        case .prototype: return "Prototype"
        case .beta:      return "Beta"
        }
    }

    var color: Color {
        switch self {
        case .concept:   return .gray
        case .prototype: return .orange
        case .beta:      return .green
        }
    }
}

// MARK: - ExperimentInfo

/// Metadata describing a single experimental feature.
struct ExperimentInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let status: ExperimentStatus
}

// MARK: - FeatureFlags

/// Singleton that persists experimental feature toggles via @AppStorage.
///
/// Observed by views throughout the app to gate access to features that are
/// still in development. Each toggle corresponds to one experimental capability.
@MainActor
final class FeatureFlags: ObservableObject {

    static let shared = FeatureFlags()

    // MARK: - Persisted Toggles

    @AppStorage("exp_lipShapeMatching")
    var lipShapeMatching: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("exp_liveCameraAR")
    var liveCameraAR: Bool = false {
        willSet { objectWillChange.send() }
    }

    @AppStorage("exp_aiVoiceCloning")
    var aiVoiceCloning: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Experiment Catalog

    /// Ordered list of all experiments with their metadata.
    static let experiments: [ExperimentInfo] = [
        ExperimentInfo(
            id: "lipShapeMatching",
            name: "Lip-Shape Matching",
            description: "Maps audio phonemes to precise mouth shapes (visemes) for more realistic animation instead of simple open/close amplitude mapping.",
            icon: "mouth",
            status: .concept
        ),
        ExperimentInfo(
            id: "liveCameraAR",
            name: "Live Camera AR",
            description: "Point your camera at your pet and see mouth animation overlaid in real time using ARKit and the Vision framework.",
            icon: "camera.viewfinder",
            status: .prototype
        ),
        ExperimentInfo(
            id: "aiVoiceCloning",
            name: "AI Voice Cloning",
            description: "Record voice samples to train a personalized voice model, then generate speech in that voice from text input.",
            icon: "waveform.and.person.filled",
            status: .concept
        ),
    ]

    // MARK: - Accessors

    /// Returns the current toggle value for a given experiment by its id.
    func isEnabled(_ experimentId: String) -> Bool {
        switch experimentId {
        case "lipShapeMatching": return lipShapeMatching
        case "liveCameraAR":    return liveCameraAR
        case "aiVoiceCloning":  return aiVoiceCloning
        default:                return false
        }
    }

    /// Sets the toggle value for a given experiment by its id.
    func setEnabled(_ experimentId: String, value: Bool) {
        switch experimentId {
        case "lipShapeMatching": lipShapeMatching = value
        case "liveCameraAR":    liveCameraAR = value
        case "aiVoiceCloning":  aiVoiceCloning = value
        default: break
        }
    }

    /// Returns true when any experimental feature is currently enabled.
    var hasAnyEnabled: Bool {
        lipShapeMatching || liveCameraAR || aiVoiceCloning
    }

    /// The number of experiments currently enabled.
    var enabledCount: Int {
        [lipShapeMatching, liveCameraAR, aiVoiceCloning].filter { $0 }.count
    }

    private init() {}
}
