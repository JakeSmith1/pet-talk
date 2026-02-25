import AVFoundation
import Combine

/// Service responsible for mixing voice audio with background music tracks.
/// Supports real-time preview via dual AVAudioPlayerNodes and offline export via AVMutableComposition.
@MainActor
final class AudioMixer: ObservableObject {

    // MARK: - Published State

    /// The selected background music URL.
    @Published var backgroundMusicURL: URL?

    /// Voice track volume (0.0 ... 1.0).
    @Published var voiceVolume: Float = 1.0

    /// Background music volume (0.0 ... 1.0).
    @Published var musicVolume: Float = 0.3

    /// Whether background music mixing is enabled.
    @Published var isMusicEnabled: Bool = false

    // MARK: - Preview Engine

    private var previewEngine: AVAudioEngine?
    private var voicePlayerNode: AVAudioPlayerNode?
    private var musicPlayerNode: AVAudioPlayerNode?
    private var voiceMixerNode: AVAudioMixerNode?
    private var musicMixerNode: AVAudioMixerNode?

    /// Whether the preview is currently playing.
    @Published var isPreviewing: Bool = false

    // MARK: - Mix Audio (Offline Export)

    /// Mixes voice and optional background music into a single audio file using AVMutableComposition.
    /// - Parameters:
    ///   - voiceURL: URL to the voice audio file.
    ///   - musicURL: Optional URL to the background music file. Pass nil to skip mixing.
    ///   - voiceVolume: Volume level for the voice track (0.0 ... 1.0).
    ///   - musicVolume: Volume level for the music track (0.0 ... 1.0).
    /// - Returns: URL to the mixed output .m4a file.
    nonisolated func mixAudio(
        voiceURL: URL,
        musicURL: URL?,
        voiceVolume: Float,
        musicVolume: Float
    ) async throws -> URL {
        guard let musicURL else {
            // No music to mix -- return voice as-is
            return voiceURL
        }

        let voiceAsset = AVURLAsset(url: voiceURL)
        let musicAsset = AVURLAsset(url: musicURL)

        let voiceDuration = try await voiceAsset.load(.duration)
        let voiceTracks = try await voiceAsset.loadTracks(withMediaType: .audio)
        let musicTracks = try await musicAsset.loadTracks(withMediaType: .audio)

        guard let voiceTrack = voiceTracks.first else {
            throw AudioMixerError.missingAudioTrack("voice")
        }
        guard let musicTrack = musicTracks.first else {
            throw AudioMixerError.missingAudioTrack("music")
        }

        // Build composition
        let composition = AVMutableComposition()

        // Add voice track
        guard let voiceCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMixerError.compositionFailed
        }

        let voiceTimeRange = CMTimeRange(start: .zero, duration: voiceDuration)
        try voiceCompositionTrack.insertTimeRange(voiceTimeRange, of: voiceTrack, at: .zero)

        // Add music track (trimmed or looped to match voice duration)
        guard let musicCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMixerError.compositionFailed
        }

        let musicDuration = try await musicAsset.load(.duration)
        try insertMusicTrack(
            musicTrack: musicTrack,
            musicDuration: musicDuration,
            into: musicCompositionTrack,
            targetDuration: voiceDuration
        )

        // Audio mix parameters for volume control
        let audioMix = AVMutableAudioMix()

        let voiceParams = AVMutableAudioMixInputParameters(track: voiceCompositionTrack)
        voiceParams.setVolume(voiceVolume, at: .zero)
        voiceParams.trackID = voiceCompositionTrack.trackID

        let musicParams = AVMutableAudioMixInputParameters(track: musicCompositionTrack)
        musicParams.setVolume(musicVolume, at: .zero)
        musicParams.trackID = musicCompositionTrack.trackID

        audioMix.inputParameters = [voiceParams, musicParams]

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioMixerError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMix

        await exportSession.export()

        guard exportSession.status == .completed else {
            let message = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw AudioMixerError.exportFailed(message)
        }

        return outputURL
    }

    // MARK: - Real-Time Preview

    /// Starts a real-time preview playing voice and optional music simultaneously using dual player nodes.
    /// - Parameters:
    ///   - voiceURL: URL to the voice audio file.
    ///   - musicURL: Optional URL to the background music file.
    func startPreview(voiceURL: URL, musicURL: URL?) {
        stopPreview()

        do {
            let engine = AVAudioEngine()

            // Voice chain
            let voicePlayer = AVAudioPlayerNode()
            let voiceMixer = AVAudioMixerNode()
            engine.attach(voicePlayer)
            engine.attach(voiceMixer)

            let voiceFile = try AVAudioFile(forReading: voiceURL)
            let voiceFormat = voiceFile.processingFormat

            engine.connect(voicePlayer, to: voiceMixer, format: voiceFormat)
            voiceMixer.outputVolume = voiceVolume

            // Music chain (optional)
            var musicPlayer: AVAudioPlayerNode?
            var musicMixer: AVAudioMixerNode?
            var musicFile: AVAudioFile?

            if let musicURL {
                let mPlayer = AVAudioPlayerNode()
                let mMixer = AVAudioMixerNode()
                engine.attach(mPlayer)
                engine.attach(mMixer)

                let mFile = try AVAudioFile(forReading: musicURL)
                let musicFormat = mFile.processingFormat

                engine.connect(mPlayer, to: mMixer, format: musicFormat)
                mMixer.outputVolume = musicVolume

                engine.connect(mMixer, to: engine.mainMixerNode, format: musicFormat)

                musicPlayer = mPlayer
                musicMixer = mMixer
                musicFile = mFile
            }

            engine.connect(voiceMixer, to: engine.mainMixerNode, format: voiceFormat)

            try engine.start()

            // Schedule and play voice
            voicePlayer.scheduleFile(voiceFile, at: nil) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.stopPreview()
                }
            }
            voicePlayer.play()

            // Schedule and play music (looping is not needed for preview -- just play once)
            if let musicPlayer, let musicFile {
                musicPlayer.scheduleFile(musicFile, at: nil)
                musicPlayer.play()
            }

            // Store references
            previewEngine = engine
            voicePlayerNode = voicePlayer
            self.voiceMixerNode = voiceMixer
            self.musicPlayerNode = musicPlayer
            self.musicMixerNode = musicMixer
            isPreviewing = true

        } catch {
            // Silently fail preview -- user can still export
            stopPreview()
        }
    }

    /// Updates the volume levels of both tracks during live preview.
    /// - Parameters:
    ///   - voice: Voice volume (0.0 ... 1.0).
    ///   - music: Music volume (0.0 ... 1.0).
    func setVolumes(voice: Float, music: Float) {
        voiceVolume = voice
        musicVolume = music
        voiceMixerNode?.outputVolume = voice
        musicMixerNode?.outputVolume = music
    }

    /// Stops the preview engine and releases all audio nodes.
    func stopPreview() {
        voicePlayerNode?.stop()
        musicPlayerNode?.stop()
        previewEngine?.stop()

        voicePlayerNode = nil
        musicPlayerNode = nil
        voiceMixerNode = nil
        musicMixerNode = nil
        previewEngine = nil
        isPreviewing = false
    }

    // MARK: - Helpers

    /// Inserts the music track into the composition track, looping if necessary to fill the target duration.
    private nonisolated func insertMusicTrack(
        musicTrack: AVAssetTrack,
        musicDuration: CMTime,
        into compositionTrack: AVMutableCompositionTrack,
        targetDuration: CMTime
    ) throws {
        var currentTime = CMTime.zero
        let targetSeconds = CMTimeGetSeconds(targetDuration)
        let musicSeconds = CMTimeGetSeconds(musicDuration)

        guard musicSeconds > 0 else { return }

        while CMTimeGetSeconds(currentTime) < targetSeconds {
            let remaining = CMTimeSubtract(targetDuration, currentTime)
            let insertDuration = CMTimeMinimum(musicDuration, remaining)
            let timeRange = CMTimeRange(start: .zero, duration: insertDuration)

            try compositionTrack.insertTimeRange(timeRange, of: musicTrack, at: currentTime)
            currentTime = CMTimeAdd(currentTime, insertDuration)
        }
    }
}

// MARK: - Errors

enum AudioMixerError: LocalizedError {
    case missingAudioTrack(String)
    case compositionFailed
    case exportSessionCreationFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioTrack(let track):
            return "The \(track) file contains no audio tracks."
        case .compositionFailed:
            return "Failed to create the audio composition."
        case .exportSessionCreationFailed:
            return "Failed to create the audio export session."
        case .exportFailed(let message):
            return "Audio mix export failed: \(message)"
        }
    }
}
