import AVFoundation
import Combine
import Foundation

// MARK: - VoiceSample

/// A single voice recording used to train the cloning model.
struct VoiceSample: Identifiable {
    let id: UUID
    /// Display label (e.g., "Sample 1").
    let label: String
    /// File URL of the recorded audio.
    let url: URL
    /// Duration in seconds.
    let duration: TimeInterval
    /// When the sample was recorded.
    let recordedAt: Date
}

// MARK: - CloningModelState

/// The training state of the voice cloning model.
enum CloningModelState: Equatable {
    case untrained
    case training(progress: Double)
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isTraining: Bool {
        if case .training = self { return true }
        return false
    }
}

// MARK: - SynthesisResult

/// The output of a voice synthesis operation.
struct SynthesisResult: Identifiable {
    let id = UUID()
    /// The text that was synthesized.
    let inputText: String
    /// URL to the generated audio file.
    let audioURL: URL
    /// Duration of the generated audio.
    let duration: TimeInterval
    /// When the synthesis was performed.
    let generatedAt: Date
}

// MARK: - VoiceCloningService

/// Stub service for AI voice cloning.
///
/// Manages voice sample collection, model training, and text-to-speech synthesis
/// using a cloned voice. All heavy operations are stubs that simulate work with
/// delays and placeholder outputs.
///
/// **Current status: Concept** -- no actual ML model is used.
@MainActor
final class VoiceCloningService: ObservableObject {

    // MARK: - Published State

    @Published var samples: [VoiceSample] = []
    @Published var modelState: CloningModelState = .untrained
    @Published var synthesisResults: [SynthesisResult] = []

    /// Whether a recording is currently in progress.
    @Published var isRecording = false

    /// Current recording level (0...1) for UI metering.
    @Published var recordingLevel: Float = 0

    // MARK: - Configuration

    /// Minimum number of samples required before training can begin.
    static let minimumSamples = 3

    /// Maximum number of samples the service will accept.
    static let maximumSamples = 10

    /// Recommended duration per sample, in seconds.
    static let recommendedSampleDuration: TimeInterval = 10

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?

    // MARK: - Sample Management

    /// Whether enough samples have been collected to begin training.
    var canTrain: Bool {
        samples.count >= Self.minimumSamples && !modelState.isTraining
    }

    /// Whether the maximum sample count has been reached.
    var isSampleLimitReached: Bool {
        samples.count >= Self.maximumSamples
    }

    /// Starts recording a new voice sample.
    func startRecording() throws {
        guard !isRecording else { return }
        guard !isSampleLimitReached else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_sample_\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw VoiceCloningError.recordingFailed
        }

        audioRecorder = recorder
        isRecording = true

        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLevel()
            }
        }
    }

    /// Stops the current recording and adds it to the sample list.
    func stopRecording() {
        levelTimer?.invalidate()
        levelTimer = nil

        guard let recorder = audioRecorder, isRecording else { return }

        let duration = recorder.currentTime
        recorder.stop()
        let url = recorder.url

        audioRecorder = nil
        isRecording = false
        recordingLevel = 0

        let sample = VoiceSample(
            id: UUID(),
            label: "Sample \(samples.count + 1)",
            url: url,
            duration: duration,
            recordedAt: Date()
        )
        samples.append(sample)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Removes a sample from the collection.
    func removeSample(_ sample: VoiceSample) {
        samples.removeAll { $0.id == sample.id }
        try? FileManager.default.removeItem(at: sample.url)

        // If we drop below threshold and model was trained, reset.
        if samples.count < Self.minimumSamples && modelState.isReady {
            modelState = .untrained
        }
    }

    /// Removes all collected samples and resets the model.
    func removeAllSamples() {
        for sample in samples {
            try? FileManager.default.removeItem(at: sample.url)
        }
        samples.removeAll()
        modelState = .untrained
        synthesisResults.removeAll()
    }

    // MARK: - Training

    /// Begins training the voice cloning model from collected samples.
    ///
    /// > Important: This is a **stub**. It simulates a training process with a
    /// > progress animation over several seconds. No actual model training occurs.
    func trainModel() async {
        guard canTrain else { return }

        modelState = .training(progress: 0)

        // Simulate training over ~3 seconds.
        let steps = 20
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms per step
            let progress = Double(step) / Double(steps)
            modelState = .training(progress: progress)
        }

        modelState = .ready
    }

    // MARK: - Synthesis

    /// Generates speech audio from the given text using the cloned voice.
    ///
    /// - Parameter text: The text to synthesize.
    /// - Returns: A `SynthesisResult` containing the generated audio.
    ///
    /// > Important: This is a **stub**. It creates a short silent audio file
    /// > as a placeholder. No actual speech synthesis is performed.
    func synthesize(text: String) async throws -> SynthesisResult {
        guard modelState.isReady else {
            throw VoiceCloningError.modelNotReady
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceCloningError.emptyText
        }

        // Simulate synthesis latency.
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s

        // Create a placeholder silent audio file.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("synth_\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let estimatedDuration: TimeInterval = Double(text.count) * 0.06 // rough estimate

        // Write a minimal silent AAC file as placeholder.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        if let format = AVAudioFormat(settings: settings) {
            let file = try? AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            // Create a buffer of silence
            let sampleCount = AVAudioFrameCount(44100 * estimatedDuration)
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(sampleCount, 1)) {
                buffer.frameLength = max(sampleCount, 1)
                try? file?.write(from: buffer)
            }
        }

        let result = SynthesisResult(
            inputText: text,
            audioURL: outputURL,
            duration: estimatedDuration,
            generatedAt: Date()
        )

        synthesisResults.insert(result, at: 0)
        return result
    }

    // MARK: - Private Helpers

    private func updateLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let dB = recorder.averagePower(forChannel: 0)
        let linear = powf(10, dB / 20.0)
        recordingLevel = min(max(linear * 3.0, 0), 1)
    }
}

// MARK: - Errors

enum VoiceCloningError: LocalizedError {
    case recordingFailed
    case modelNotReady
    case emptyText
    case synthesizeFailed

    var errorDescription: String? {
        switch self {
        case .recordingFailed:
            return "Failed to start voice recording. Please check microphone permissions."
        case .modelNotReady:
            return "The voice model has not been trained yet. Please record samples and train first."
        case .emptyText:
            return "Please enter some text to synthesize."
        case .synthesizeFailed:
            return "Voice synthesis failed. Please try again."
        }
    }
}
