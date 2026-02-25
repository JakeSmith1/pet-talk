import Foundation
import CoreGraphics
import UIKit

/// Represents the detected mouth region on the pet's face.
/// Coordinates use Vision's normalized space (origin at bottom-left, range 0...1).
struct MouthRegion: Equatable {
    /// Center point in Vision's normalized coordinate space (origin bottom-left, 0...1).
    let center: CGPoint
    /// Estimated radius in normalized image coordinates
    let radius: CGFloat
}

/// The main data model tracking state through the app flow
@MainActor
final class PetTalkProject: ObservableObject {
    /// The selected pet photo
    @Published var image: UIImage?
    /// The detected mouth region (normalized coordinates)
    @Published var mouthRegion: MouthRegion?
    /// URL to the recorded/imported audio file
    @Published var audioURL: URL?
    /// URL to the exported video file
    @Published var exportedVideoURL: URL?
    /// Pre-analyzed amplitude values at 30fps (populated by PreviewView)
    @Published var amplitudes: [Float] = []
    /// Pitch shift in semitones (-12...+12)
    @Published var pitchShift: Float = 0
    /// URL to the pitch-shifted audio file for export (nil when pitchShift == 0)
    @Published var processedAudioURL: URL?
    /// The selected export format (Video, GIF, or Sticker Pack)
    @Published var exportFormat: ExportFormat = .video
    /// The selected sound effect from the built-in library (nil when recording or importing).
    @Published var selectedSoundEffect: SoundEffect?

    // MARK: - Visual Effects

    /// Whether eye blink/eyebrow animation is enabled.
    @Published var enableEyeAnimation: Bool = false
    /// Detected eye region (populated alongside mouthRegion during detection).
    @Published var eyeRegion: EyeRegion?
    /// Currently selected accessory placements.
    @Published var selectedAccessories: [AccessoryPlacement] = []
    /// Selected gradient background scene (nil = original background).
    @Published var selectedBackground: BackgroundScene?
    /// Custom photo to use as background (takes precedence when non-nil).
    @Published var customBackgroundImage: UIImage?
    /// Selected cartoon filter preset.
    @Published var selectedFilter: CartoonFilterPreset = .none

    // MARK: - Multi-Track Dubbing

    /// URL to the selected background music track
    @Published var backgroundMusicURL: URL?
    /// Voice volume for mixing (0.0 ... 1.0)
    @Published var voiceVolume: Float = 1.0
    /// Background music volume for mixing (0.0 ... 1.0)
    @Published var musicVolume: Float = 0.3
    /// URL to the final mixed audio file (voice + background music)
    @Published var mixedAudioURL: URL?

    /// Current step in the workflow
    @Published var currentStep: Step = .pickPhoto

    // MARK: - Project Save/Load Properties

    /// User-provided name for the project (populated when saving or loading).
    @Published var projectName: String?
    /// ID of the saved project on disk (nil if never saved).
    @Published var savedProjectId: UUID?

    enum Step: Int, CaseIterable {
        case pickPhoto = 0
        case recordAudio = 1
        case preview = 2
        case export = 3
    }

    func reset() {
        for url in [audioURL, processedAudioURL, mixedAudioURL, exportedVideoURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        image = nil
        mouthRegion = nil
        audioURL = nil
        exportedVideoURL = nil
        amplitudes = []
        pitchShift = 0
        processedAudioURL = nil
        exportFormat = .video
        selectedSoundEffect = nil
        backgroundMusicURL = nil
        voiceVolume = 1.0
        musicVolume = 0.3
        mixedAudioURL = nil
        enableEyeAnimation = false
        eyeRegion = nil
        selectedAccessories = []
        selectedBackground = nil
        customBackgroundImage = nil
        selectedFilter = .none
        projectName = nil
        savedProjectId = nil
        currentStep = .pickPhoto
    }
}
