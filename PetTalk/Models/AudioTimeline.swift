import AVFoundation
import Accelerate

/// Represents a trim range on an audio file, expressed as fractions of total duration (0...1).
struct TrimRange: Equatable {
    /// Start position as a fraction of total duration (0...1).
    var start: Double = 0
    /// End position as a fraction of total duration (0...1).
    var end: Double = 1

    /// The fractional length of the trimmed region.
    var length: Double { end - start }

    /// Whether this represents the full, untrimmed audio.
    var isFullRange: Bool {
        start <= 0.001 && end >= 0.999
    }
}

/// Manages audio timeline state including trim range, undo/redo history,
/// and waveform sample generation for visualization.
@MainActor
final class AudioTimeline: ObservableObject {

    // MARK: - Published State

    /// The current trim range.
    @Published var trimRange: TrimRange = TrimRange()

    /// Normalized waveform samples (0...1) for drawing. Typically 200-400 samples.
    @Published var waveformSamples: [Float] = []

    /// Total duration of the source audio in seconds.
    @Published var duration: TimeInterval = 0

    /// Current playback position as a fraction of total duration (0...1).
    @Published var playbackPosition: Double = 0

    /// Whether waveform data is currently being generated.
    @Published var isAnalyzing: Bool = false

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Undo / Redo

    private var undoStack: [TrimRange] = []
    private var redoStack: [TrimRange] = []

    /// Saves the current trim range to the undo stack before making a change.
    func pushUndoState() {
        undoStack.append(trimRange)
        redoStack.removeAll()
    }

    /// Reverts to the previous trim range.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(trimRange)
        trimRange = previous
    }

    /// Re-applies a previously undone trim range.
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(trimRange)
        trimRange = next
    }

    /// Resets the trim to the full range and clears undo/redo history.
    func resetTrim() {
        pushUndoState()
        trimRange = TrimRange()
    }

    // MARK: - Waveform Generation

    /// Target number of waveform samples to generate for visualization.
    private static let targetSampleCount = 300

    /// Analyzes an audio file and populates `waveformSamples` and `duration`.
    /// - Parameter url: The audio file URL.
    nonisolated func generateWaveform(from url: URL) async throws {
        await MainActor.run { isAnalyzing = true }
        defer { Task { @MainActor in isAnalyzing = false } }

        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.fileFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioTimelineError.invalidFormat
        }

        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else {
            await MainActor.run {
                waveformSamples = []
                duration = 0
            }
            return
        }

        let fileDuration = Double(file.length) / file.fileFormat.sampleRate

        // Read the entire file.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw AudioTimelineError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioTimelineError.noChannelData
        }

        let sampleCount = Int(buffer.frameLength)
        let targetCount = Self.targetSampleCount
        let samplesPerBucket = max(1, sampleCount / targetCount)

        var samples: [Float] = []
        samples.reserveCapacity(targetCount)

        var offset = 0
        while offset < sampleCount {
            let remaining = sampleCount - offset
            let count = min(samplesPerBucket, remaining)

            // Compute RMS for this bucket.
            var meanSquare: Float = 0
            vDSP_measqv(channelData + offset, 1, &meanSquare, vDSP_Length(count))
            let rms = sqrtf(meanSquare)
            samples.append(rms)

            offset += samplesPerBucket
        }

        // Normalize to 0...1 based on peak value.
        let peak = samples.max() ?? 1.0
        if peak > .ulpOfOne {
            samples = samples.map { min($0 / peak, 1.0) }
        }

        await MainActor.run {
            waveformSamples = samples
            duration = fileDuration
        }
    }

    // MARK: - Computed Properties

    /// The trim start time in seconds.
    var trimStartTime: TimeInterval {
        duration * trimRange.start
    }

    /// The trim end time in seconds.
    var trimEndTime: TimeInterval {
        duration * trimRange.end
    }

    /// The trimmed duration in seconds.
    var trimmedDuration: TimeInterval {
        duration * trimRange.length
    }
}

// MARK: - Errors

enum AudioTimelineError: LocalizedError {
    case invalidFormat
    case bufferAllocationFailed
    case noChannelData

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not create a suitable audio format for waveform analysis."
        case .bufferAllocationFailed:
            return "Failed to allocate an audio buffer for waveform analysis."
        case .noChannelData:
            return "The audio file contained no readable channel data."
        }
    }
}
