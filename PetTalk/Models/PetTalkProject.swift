import Foundation
import CoreGraphics
import UIKit

/// Represents the detected mouth region on the pet's face
struct MouthRegion: Equatable {
    /// Center point in normalized image coordinates (0...1)
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

    /// Current step in the workflow
    @Published var currentStep: Step = .pickPhoto

    enum Step: Int, CaseIterable {
        case pickPhoto = 0
        case recordAudio = 1
        case preview = 2
        case export = 3
    }

    func reset() {
        image = nil
        mouthRegion = nil
        audioURL = nil
        exportedVideoURL = nil
        currentStep = .pickPhoto
    }
}
