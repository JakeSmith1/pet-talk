import Foundation

/// A pre-built sound effect available in the Sound Effects Library.
struct SoundEffect: Identifiable, Codable, Hashable {
    /// Unique identifier for the effect (e.g. "bark_small_01").
    let id: String
    /// Human-readable display name.
    let name: String
    /// The category this effect belongs to.
    let category: Category
    /// The file name (without extension) stored in the app bundle.
    let fileName: String
    /// Duration in seconds.
    let duration: TimeInterval

    enum Category: String, Codable, CaseIterable {
        case bark = "Barks"
        case meow = "Meows"
        case funny = "Funny"
        case phrases = "Phrases"
    }
}
