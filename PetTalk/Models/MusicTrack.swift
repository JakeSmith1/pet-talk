import Foundation

/// A background music track available for dubbing over voice audio.
struct MusicTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let category: Category
    /// Filename (without extension) of the bundled audio resource, or nil for user-imported tracks.
    let bundledFilename: String?
    /// URL for user-imported tracks from Files app. Nil for bundled tracks.
    let importedURL: URL?
    /// Estimated duration in seconds (for display purposes).
    let durationSeconds: TimeInterval

    enum Category: String, CaseIterable, Identifiable {
        case upbeat = "Upbeat"
        case chill = "Chill"
        case funny = "Funny"
        case dramatic = "Dramatic"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .upbeat: return "bolt.fill"
            case .chill: return "leaf.fill"
            case .funny: return "face.smiling.fill"
            case .dramatic: return "theatermasks.fill"
            }
        }
    }

    /// Resolves the playback URL for this track.
    var url: URL? {
        if let importedURL {
            return importedURL
        }
        guard let filename = bundledFilename else { return nil }
        return Bundle.main.url(forResource: filename, withExtension: "m4a")
            ?? Bundle.main.url(forResource: filename, withExtension: "mp3")
            ?? Bundle.main.url(forResource: filename, withExtension: "wav")
    }
}

// MARK: - Built-in Catalog

extension MusicTrack {

    /// The built-in catalog of background music tracks shipped with the app.
    static let catalog: [MusicTrack] = [
        // Upbeat
        MusicTrack(id: "upbeat_playful_paws", name: "Playful Paws", category: .upbeat,
                   bundledFilename: "playful_paws", importedURL: nil, durationSeconds: 30),
        MusicTrack(id: "upbeat_happy_tails", name: "Happy Tails", category: .upbeat,
                   bundledFilename: "happy_tails", importedURL: nil, durationSeconds: 25),
        MusicTrack(id: "upbeat_zoomies", name: "Zoomies", category: .upbeat,
                   bundledFilename: "zoomies", importedURL: nil, durationSeconds: 20),

        // Chill
        MusicTrack(id: "chill_lazy_afternoon", name: "Lazy Afternoon", category: .chill,
                   bundledFilename: "lazy_afternoon", importedURL: nil, durationSeconds: 35),
        MusicTrack(id: "chill_purr_vibes", name: "Purr Vibes", category: .chill,
                   bundledFilename: "purr_vibes", importedURL: nil, durationSeconds: 30),
        MusicTrack(id: "chill_nap_time", name: "Nap Time", category: .chill,
                   bundledFilename: "nap_time", importedURL: nil, durationSeconds: 28),

        // Funny
        MusicTrack(id: "funny_silly_walk", name: "Silly Walk", category: .funny,
                   bundledFilename: "silly_walk", importedURL: nil, durationSeconds: 18),
        MusicTrack(id: "funny_derp_mode", name: "Derp Mode", category: .funny,
                   bundledFilename: "derp_mode", importedURL: nil, durationSeconds: 22),
        MusicTrack(id: "funny_boing", name: "Boing!", category: .funny,
                   bundledFilename: "boing", importedURL: nil, durationSeconds: 15),

        // Dramatic
        MusicTrack(id: "dramatic_epic_entrance", name: "Epic Entrance", category: .dramatic,
                   bundledFilename: "epic_entrance", importedURL: nil, durationSeconds: 32),
        MusicTrack(id: "dramatic_the_stare", name: "The Stare", category: .dramatic,
                   bundledFilename: "the_stare", importedURL: nil, durationSeconds: 27),
        MusicTrack(id: "dramatic_villain_cat", name: "Villain Cat", category: .dramatic,
                   bundledFilename: "villain_cat", importedURL: nil, durationSeconds: 24),
    ]

    /// Returns catalog tracks filtered by category.
    static func tracks(for category: Category) -> [MusicTrack] {
        catalog.filter { $0.category == category }
    }

    /// Creates a user-imported track from a file URL.
    static func imported(url: URL, name: String, duration: TimeInterval) -> MusicTrack {
        MusicTrack(
            id: "imported_\(UUID().uuidString)",
            name: name,
            category: .chill, // Default category for imported tracks
            bundledFilename: nil,
            importedURL: url,
            durationSeconds: duration
        )
    }
}
