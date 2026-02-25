import Foundation

/// Codable metadata model for a saved PetTalk project.
/// The actual image and audio files are stored alongside this metadata in the project directory.
struct SavedProject: Codable, Identifiable, Equatable {
    /// Unique identifier for this saved project.
    let id: UUID
    /// User-provided name for the project.
    var name: String
    /// Date the project was created.
    let createdAt: Date
    /// Date the project was last modified.
    var modifiedAt: Date
    /// File name of the saved pet image (relative to the project directory).
    let imageFileName: String
    /// File name of the saved audio file (relative to the project directory).
    let audioFileName: String
    /// The detected/adjusted mouth region.
    let mouthRegion: CodableMouthRegion
    /// Pitch shift in semitones.
    var pitchShift: Float
    /// Optional thumbnail file name for quick display in the project list.
    let thumbnailFileName: String

    /// The metadata file name used within each project directory.
    static let metadataFileName = "project.json"
}

/// A Codable wrapper for MouthRegion since CGPoint and CGFloat are not directly Codable
/// in a cross-platform-safe way.
struct CodableMouthRegion: Codable, Equatable {
    let centerX: Double
    let centerY: Double
    let radius: Double

    init(from region: MouthRegion) {
        self.centerX = Double(region.center.x)
        self.centerY = Double(region.center.y)
        self.radius = Double(region.radius)
    }

    func toMouthRegion() -> MouthRegion {
        MouthRegion(
            center: CGPoint(x: centerX, y: centerY),
            radius: CGFloat(radius)
        )
    }
}
