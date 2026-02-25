import Foundation
import UIKit

// MARK: - Duet Pet Track

/// Represents one pet's data in a duet composition.
/// Each track has its own image, mouth region, audio, and pitch settings.
@MainActor
final class PetTrack: ObservableObject, Identifiable {
    let id: UUID

    /// The pet photo for this track.
    @Published var image: UIImage?

    /// The detected mouth region (normalized Vision coordinates).
    @Published var mouthRegion: MouthRegion?

    /// URL to the recorded/imported audio file.
    @Published var audioURL: URL?

    /// Pre-analyzed amplitude values at 30fps.
    @Published var amplitudes: [Float] = []

    /// Pitch shift in semitones (-12...+12).
    @Published var pitchShift: Float = 0

    /// URL to the pitch-shifted audio file (nil when pitchShift == 0).
    @Published var processedAudioURL: URL?

    /// Display label for this track (e.g., "Left Pet", "Right Pet").
    let label: String

    /// Whether this track has all required data for preview/export.
    var isReady: Bool {
        image != nil && mouthRegion != nil && audioURL != nil
    }

    /// The effective audio URL, considering pitch processing.
    var effectiveAudioURL: URL? {
        processedAudioURL ?? audioURL
    }

    init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }

    func reset() {
        for url in [audioURL, processedAudioURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        image = nil
        mouthRegion = nil
        audioURL = nil
        amplitudes = []
        pitchShift = 0
        processedAudioURL = nil
    }
}

// MARK: - Duet Project

/// Manages a side-by-side "duet" composition of two talking pets.
@MainActor
final class DuetProject: ObservableObject {

    /// The left pet track.
    @Published var leftTrack: PetTrack

    /// The right pet track.
    @Published var rightTrack: PetTrack

    /// URL to the exported duet video.
    @Published var exportedVideoURL: URL?

    /// The current setup step.
    @Published var currentStep: DuetStep = .setupLeft

    /// Whether both tracks are fully configured and ready for preview.
    var isReadyForPreview: Bool {
        leftTrack.isReady && rightTrack.isReady
    }

    init() {
        self.leftTrack = PetTrack(label: "Left Pet")
        self.rightTrack = PetTrack(label: "Right Pet")
    }

    func reset() {
        if let url = exportedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        leftTrack.reset()
        rightTrack.reset()
        exportedVideoURL = nil
        currentStep = .setupLeft
    }
}

// MARK: - Duet Step

enum DuetStep: Int, CaseIterable {
    case setupLeft = 0
    case setupRight = 1
    case preview = 2
    case export = 3

    var title: String {
        switch self {
        case .setupLeft: return "Left Pet"
        case .setupRight: return "Right Pet"
        case .preview: return "Duet Preview"
        case .export: return "Export Duet"
        }
    }
}

// MARK: - Duet Layout

/// Configuration for the side-by-side video layout.
struct DuetLayout: Equatable {
    /// Output video dimensions.
    var outputSize: CGSize = CGSize(width: 1920, height: 1080)

    /// Gap between the two pet panels in pixels.
    var dividerWidth: CGFloat = 4

    /// Background color for the divider and any letterboxing.
    var backgroundColor: CGColor = UIColor.black.cgColor

    /// Whether to show pet labels overlaid on the video.
    var showLabels: Bool = false

    /// Individual panel size (computed).
    var panelSize: CGSize {
        let panelWidth = (outputSize.width - dividerWidth) / 2
        return CGSize(width: panelWidth, height: outputSize.height)
    }

    static let `default` = DuetLayout()

    static let square = DuetLayout(
        outputSize: CGSize(width: 1080, height: 1080)
    )

    static let portrait = DuetLayout(
        outputSize: CGSize(width: 1080, height: 1920)
    )
}
