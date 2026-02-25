import AVFoundation

/// Trims an audio file to a specified time range using AVAssetExportSession,
/// producing a new .m4a file.
enum AudioTrimmer {

    /// Trims the audio file at `sourceURL` to the specified time range and writes
    /// the result to a new temporary .m4a file.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the source audio file.
    ///   - startTime: Start time in seconds.
    ///   - endTime: End time in seconds.
    /// - Returns: URL of the trimmed audio file.
    /// - Throws: `AudioTrimmerError` if the operation fails.
    static func trim(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Validate the asset has audio.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioTrimmerError.noAudioTrack
        }

        let assetDuration = try await asset.load(.duration)
        let assetDurationSeconds = CMTimeGetSeconds(assetDuration)
        guard assetDurationSeconds > 0 else {
            throw AudioTrimmerError.zeroDuration
        }

        // Clamp the requested range to the actual file duration.
        let clampedStart = max(0, min(startTime, assetDurationSeconds))
        let clampedEnd = max(clampedStart + 0.01, min(endTime, assetDurationSeconds))

        let startCMTime = CMTime(seconds: clampedStart, preferredTimescale: 44100)
        let endCMTime = CMTime(seconds: clampedEnd, preferredTimescale: 44100)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        // Prepare the output URL.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Configure the export session.
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioTrimmerError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange

        // Execute the export.
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw AudioTrimmerError.exportCancelled
        case .failed:
            throw AudioTrimmerError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        default:
            throw AudioTrimmerError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
}

// MARK: - Errors

enum AudioTrimmerError: LocalizedError {
    case noAudioTrack
    case zeroDuration
    case exportSessionCreationFailed
    case exportCancelled
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The audio file contains no audio tracks."
        case .zeroDuration:
            return "The audio file has zero duration."
        case .exportSessionCreationFailed:
            return "Could not create an audio export session."
        case .exportCancelled:
            return "Audio trim was cancelled."
        case .exportFailed(let reason):
            return "Audio trim failed: \(reason)"
        }
    }
}
