import AVFoundation
import Accelerate

/// Analyzes audio amplitude in real time (for playback) and offline (for video export).
@MainActor
final class AudioAnalyzer: ObservableObject {

    // MARK: - Published State

    /// Current amplitude in 0...1 range (updated during live playback).
    @Published var amplitude: Float = 0

    /// Whether audio is currently playing.
    @Published var isPlaying: Bool = false

    /// All amplitude samples captured by `analyzeFile(url:)` at the configured frame rate.
    @Published var amplitudes: [Float] = []

    // MARK: - Configuration

    /// Gain multiplier applied before clamping so quiet recordings remain visible.
    private let gain: Float = 3.0

    /// Smoothing factor for the exponential moving average (lower = smoother, higher = more responsive).
    private let smoothingAlpha: Float = 0.3

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?

    /// Smoothed amplitude value used by the audio tap closure.
    /// Audio taps are called sequentially by the audio engine, so concurrent access is not expected.
    nonisolated(unsafe) private var tapSmoothed: Float = 0

    // MARK: - Pre-analysis

    /// Returns the pre-analyzed amplitude for a given timestamp.
    /// - Parameters:
    ///   - time: The playback time in seconds.
    ///   - fps: The frame rate used during analysis (must match the rate passed to `analyzeFile`).
    /// - Returns: The amplitude value in 0...1, or 0 when out of range.
    func amplitudeAtTime(_ time: TimeInterval, fps: Double = 30) -> Float {
        let index = Int((time * fps).rounded(.down))
        guard index >= 0, index < amplitudes.count else { return 0 }
        return amplitudes[index]
    }

    /// Pre-analyzes the entire audio file and fills `amplitudes` with one RMS sample per frame.
    /// - Parameters:
    ///   - url: Path to the audio file.
    ///   - fps: Target frame rate (default 30).
    nonisolated func analyzeFile(url: URL, fps: Double = 30) async throws {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.fileFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioAnalyzerError.invalidFormat
        }

        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else {
            await MainActor.run { amplitudes = [] }
            return
        }

        // Read the entire file into one buffer.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw AudioAnalyzerError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioAnalyzerError.noChannelData
        }

        let sampleRate = file.fileFormat.sampleRate
        let samplesPerFrame = Int(sampleRate / fps)
        guard samplesPerFrame > 0 else {
            throw AudioAnalyzerError.invalidFrameRate
        }

        let sampleCount = Int(buffer.frameLength)
        var result: [Float] = []
        result.reserveCapacity(sampleCount / samplesPerFrame + 1)

        var smoothed: Float = 0
        var offset = 0

        while offset < sampleCount {
            let remaining = sampleCount - offset
            let count = min(samplesPerFrame, remaining)

            let rms = Self.computeRMS(channelData + offset, count: count)
            let normalized = min(rms * gain, 1.0)

            smoothed = smoothingAlpha * normalized + (1 - smoothingAlpha) * smoothed
            result.append(smoothed)

            offset += samplesPerFrame
        }

        await MainActor.run { amplitudes = result }
    }

    // MARK: - Live Playback

    /// Starts playing the audio file through an `AVAudioEngine` with pitch shifting and updates `amplitude` in real time.
    func startPlayback(url: URL) throws {
        stopPlayback()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()

        engine.attach(player)
        engine.attach(timePitch)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        // Install a tap on the mixer to compute amplitude (post pitch-shift).
        // Note: Live tap uses a fixed 1024-frame buffer, while offline analysis uses samplesPerFrame
        // (sampleRate / fps). This difference may cause slight amplitude discrepancies.
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        tapSmoothed = 0
        let alpha = smoothingAlpha
        let capturedGain = gain

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            let rms = Self.computeRMS(channelData[0], count: count)
            let normalized = min(rms * capturedGain, 1.0)
            self.tapSmoothed = alpha * normalized + (1 - alpha) * self.tapSmoothed

            let value = self.tapSmoothed
            Task { @MainActor [weak self] in
                self?.amplitude = value
            }
        }

        try engine.start()
        player.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                self?.stopPlayback()
            }
        }
        player.play()
        isPlaying = true

        audioEngine = engine
        playerNode = player
        timePitchNode = timePitch
    }

    /// Sets the real-time pitch shift in semitones.
    func setPitch(_ semitones: Float) {
        timePitchNode?.pitch = semitones * 100 // AVAudioUnitTimePitch uses cents
    }

    /// Stops playback, removes the tap, and resets amplitude to zero.
    func stopPlayback() {
        audioEngine?.mainMixerNode.removeTap(onBus: 0)
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        timePitchNode = nil
        audioEngine = nil
        amplitude = 0
        isPlaying = false
    }

    // MARK: - Offline Pitch Rendering

    /// Renders a pitch-shifted version of the input audio file to a new .m4a file.
    /// - Parameters:
    ///   - inputURL: The source audio file.
    ///   - pitchShift: Pitch shift in semitones.
    /// - Returns: URL to the rendered output file.
    nonisolated func renderProcessedAudio(inputURL: URL, pitchShift: Float) async throws -> URL {
        let sourceFile = try AVAudioFile(forReading: inputURL)
        let format = sourceFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(sourceFile.length)

        // Set up offline engine
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = pitchShift * 100

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        player.play()

        // Schedule source file
        player.scheduleFile(sourceFile, at: nil)

        // Prepare output file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        // Render in chunks
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                  frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw AudioAnalyzerError.bufferAllocationFailed
        }
        var framesRemaining = totalFrames
        var retryCount = 0
        let maxRetries = 100
        while framesRemaining > 0 {
            let framesToRender = min(engine.manualRenderingMaximumFrameCount, framesRemaining)
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                try outputFile.write(from: renderBuffer)
                framesRemaining -= renderBuffer.frameLength
                retryCount = 0
            case .insufficientDataFromInputNode:
                // Input exhausted — we're done
                framesRemaining = 0
            case .cannotDoInCurrentContext:
                retryCount += 1
                if retryCount > maxRetries {
                    throw AudioAnalyzerError.offlineRenderFailed
                }
                continue
            case .error:
                throw AudioAnalyzerError.offlineRenderFailed
            @unknown default:
                throw AudioAnalyzerError.offlineRenderFailed
            }
        }

        engine.stop()
        player.stop()
        return outputURL
    }

    // MARK: - Helpers

    /// Computes the RMS (root mean square) of a float buffer.
    private static func computeRMS(_ data: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sumOfSquares: Float = 0
        vDSP_measqv(data, 1, &sumOfSquares, vDSP_Length(count))
        return sqrtf(sumOfSquares)
    }
}

// MARK: - Errors

enum AudioAnalyzerError: LocalizedError {
    case invalidFormat
    case bufferAllocationFailed
    case noChannelData
    case invalidFrameRate
    case offlineRenderFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not create a mono Float32 audio format."
        case .bufferAllocationFailed:
            return "Failed to allocate an audio buffer."
        case .noChannelData:
            return "The audio buffer contained no channel data."
        case .invalidFrameRate:
            return "The requested frame rate is too high for the sample rate."
        case .offlineRenderFailed:
            return "Offline audio rendering failed."
        }
    }
}
