import AVFoundation
import Combine

/// Provides the catalog of built-in sound effects and handles audio preview playback.
@MainActor
final class SoundEffectLibrary: ObservableObject {

    // MARK: - Published State

    /// The effect currently being previewed, or nil if nothing is playing.
    @Published var nowPlaying: SoundEffect?

    // MARK: - Catalog

    /// The full catalog of bundled sound effects.
    static let catalog: [SoundEffect] = [
        // Barks
        SoundEffect(id: "bark_small_01", name: "Small Dog Bark", category: .bark, fileName: "bark_small_01", duration: 1.2),
        SoundEffect(id: "bark_small_02", name: "Puppy Yip", category: .bark, fileName: "bark_small_02", duration: 0.8),
        SoundEffect(id: "bark_big_01", name: "Big Dog Woof", category: .bark, fileName: "bark_big_01", duration: 1.5),
        SoundEffect(id: "bark_big_02", name: "Deep Bark", category: .bark, fileName: "bark_big_02", duration: 1.3),

        // Meows
        SoundEffect(id: "meow_short_01", name: "Short Meow", category: .meow, fileName: "meow_short_01", duration: 0.9),
        SoundEffect(id: "meow_long_01", name: "Long Meow", category: .meow, fileName: "meow_long_01", duration: 2.1),
        SoundEffect(id: "meow_purr_01", name: "Purring", category: .meow, fileName: "meow_purr_01", duration: 3.0),
        SoundEffect(id: "meow_hiss_01", name: "Cat Hiss", category: .meow, fileName: "meow_hiss_01", duration: 1.1),

        // Funny
        SoundEffect(id: "funny_boing_01", name: "Boing", category: .funny, fileName: "funny_boing_01", duration: 0.7),
        SoundEffect(id: "funny_whistle_01", name: "Slide Whistle", category: .funny, fileName: "funny_whistle_01", duration: 1.4),
        SoundEffect(id: "funny_honk_01", name: "Clown Honk", category: .funny, fileName: "funny_honk_01", duration: 0.6),
        SoundEffect(id: "funny_rimshot_01", name: "Rimshot", category: .funny, fileName: "funny_rimshot_01", duration: 1.0),

        // Phrases
        SoundEffect(id: "phrase_hello_01", name: "Hello!", category: .phrases, fileName: "phrase_hello_01", duration: 1.0),
        SoundEffect(id: "phrase_treat_01", name: "I Want a Treat", category: .phrases, fileName: "phrase_treat_01", duration: 1.8),
        SoundEffect(id: "phrase_walk_01", name: "Let's Go for a Walk", category: .phrases, fileName: "phrase_walk_01", duration: 2.2),
        SoundEffect(id: "phrase_love_01", name: "I Love You", category: .phrases, fileName: "phrase_love_01", duration: 1.5),
    ]

    /// Returns catalog entries filtered by category.
    static func effects(for category: SoundEffect.Category) -> [SoundEffect] {
        catalog.filter { $0.category == category }
    }

    // MARK: - Preview Playback

    private var audioPlayer: AVAudioPlayer?

    /// Plays a preview of the given sound effect.
    /// If a preview is already playing it is stopped first.
    func previewSound(_ effect: SoundEffect) {
        stopPreview()

        guard let url = urlForEffect(effect) else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = playbackDelegate
            player.play()
            audioPlayer = player
            nowPlaying = effect
        } catch {
            nowPlaying = nil
        }
    }

    /// Stops any sound effect preview that is currently playing.
    func stopPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        nowPlaying = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Returns the bundle URL for the given sound effect, or nil if the resource is missing.
    func urlForEffect(_ effect: SoundEffect) -> URL? {
        Bundle.main.url(forResource: effect.fileName, withExtension: "m4a")
            ?? Bundle.main.url(forResource: effect.fileName, withExtension: "mp3")
            ?? Bundle.main.url(forResource: effect.fileName, withExtension: "wav")
    }

    // MARK: - Playback Delegate

    /// A small helper that notifies the library when playback finishes naturally.
    private lazy var playbackDelegate: PlaybackDelegate = PlaybackDelegate { [weak self] in
        Task { @MainActor [weak self] in
            self?.nowPlaying = nil
        }
    }
}

// MARK: - PlaybackDelegate

/// Bridges AVAudioPlayerDelegate callbacks to a closure so the @MainActor library
/// can react without conforming to the delegate protocol itself.
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
