import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Step 2 of the PetTalk workflow — record or import audio for the pet animation.
struct AudioRecordView: View {
    @EnvironmentObject private var project: PetTalkProject

    @StateObject private var recorder = AudioRecorderModel()
    @StateObject private var timeline = AudioTimeline()

    @State private var showDocumentPicker = false
    @State private var showSoundEffectPicker = false
    @State private var isTrimming = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            levelMeter

            timeLabel

            recordingControls

            if recorder.recordedURL != nil {
                // Audio timeline with waveform and trim controls.
                AudioTimelineView(timeline: timeline)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                playbackControls
                actionButtons
            }

            Spacer()

            importButton

            soundEffectsButton
        }
        .padding()
        .sheet(isPresented: $showSoundEffectPicker) {
            SoundEffectPickerView()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                recorder.recordedURL = url
                recorder.state = .stopped
                generateWaveform()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onDisappear {
            recorder.cleanup()
        }
    }

    // MARK: - Subviews

    /// A pulsing circle that reflects the current audio level.
    private var levelMeter: some View {
        let baseSize: CGFloat = 100
        let level = CGFloat(recorder.currentLevel)
        let scale = 1.0 + level * 0.5

        return Circle()
            .fill(recorder.state == .recording ? Color.red.opacity(0.6 + level * 0.4) : Color.secondary.opacity(0.25))
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.08), value: recorder.currentLevel)
    }

    private var timeLabel: some View {
        Text(formattedTime(recorder.elapsedTime))
            .font(.system(.title, design: .monospaced))
            .foregroundStyle(recorder.state == .recording ? .primary : .secondary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.1), value: recorder.elapsedTime)
    }

    private var recordingControls: some View {
        Button {
            handleRecordToggle()
        } label: {
            ZStack {
                Circle()
                    .fill(recorder.state == .recording ? .red : .red.opacity(0.85))
                    .frame(width: 72, height: 72)

                if recorder.state == .recording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .accessibilityLabel(recorder.state == .recording ? "Stop Recording" : "Start Recording")
    }

    @ViewBuilder
    private var playbackControls: some View {
        HStack(spacing: 20) {
            Button {
                handlePlaybackToggle()
            } label: {
                Image(systemName: recorder.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel(recorder.state == .playing ? "Pause" : "Play")
        }
    }

    private var actionButtons: some View {
        Button {
            handleUseAudio()
        } label: {
            if isTrimming {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Use This Audio")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isTrimming)
    }

    private var importButton: some View {
        Button {
            showDocumentPicker = true
        } label: {
            Label("Import Audio", systemImage: "doc.badge.plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var soundEffectsButton: some View {
        Button {
            showSoundEffectPicker = true
        } label: {
            Label("Browse Sound Effects", systemImage: "waveform.badge.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func handleRecordToggle() {
        do {
            if recorder.state == .recording {
                try recorder.stopRecording()
                generateWaveform()
            } else {
                try recorder.startRecording()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handlePlaybackToggle() {
        do {
            if recorder.state == .playing {
                recorder.stopPlayback()
            } else {
                try recorder.startPlayback()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Timeline Helpers

    private func generateWaveform() {
        guard let url = recorder.recordedURL else { return }
        Task {
            do {
                try await timeline.generateWaveform(from: url)
                // Reset trim range for new audio.
                timeline.trimRange = TrimRange()
            } catch {
                errorMessage = "Waveform generation failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func handleUseAudio() {
        guard let url = recorder.recordedURL else { return }

        // If the user hasn't trimmed, use the file as-is.
        if timeline.trimRange.isFullRange {
            project.audioURL = url
            project.currentStep = .preview
            return
        }

        // Otherwise, trim the audio to the selected range.
        isTrimming = true
        Task {
            do {
                let trimmedURL = try await AudioTrimmer.trim(
                    sourceURL: url,
                    startTime: timeline.trimStartTime,
                    endTime: timeline.trimEndTime
                )
                project.audioURL = trimmedURL
                isTrimming = false
                project.currentStep = .preview
            } catch {
                isTrimming = false
                errorMessage = "Trim failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - Helpers

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%01d:%02d", mins, secs)
    }
}

// MARK: - AudioRecorderModel

/// Manages recording, playback, level metering, and the 30-second auto-stop timer.
@MainActor
final class AudioRecorderModel: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case stopped
        case playing
    }

    @Published var state: State = .idle
    @Published var currentLevel: Float = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var recordedURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    private var playbackTimer: Timer?

    private static let maxDuration: TimeInterval = 30

    // MARK: - Recording

    func startRecording() throws {
        try configureAudioSession()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw RecordingError.couldNotStart
        }

        audioRecorder = recorder
        recordedURL = url
        state = .recording
        elapsedTime = 0

        // Level metering timer (~30 fps).
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetering()
            }
        }

        // Duration / auto-stop timer (1 Hz).
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }

    func stopRecording() throws {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        currentLevel = 0
        state = .stopped
        deactivateAudioSession()
    }

    // MARK: - Playback

    func startPlayback() throws {
        guard let url = recordedURL else { return }

        let player = try AVAudioPlayer(contentsOf: url)
        player.play()
        audioPlayer = player
        state = .playing

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.audioPlayer?.isPlaying != true {
                    self.stopPlayback()
                }
            }
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        state = .stopped
    }

    // MARK: - Cleanup

    func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        state = .idle
        deactivateAudioSession()
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()

        // averagePower is in dBFS (–160 ... 0). Map to 0...1.
        let dB = recorder.averagePower(forChannel: 0)
        let linear = powf(10, dB / 20.0)          // Convert dBFS to linear amplitude.
        let clamped = min(max(linear * 3.0, 0), 1) // Apply gain and clamp.
        currentLevel = clamped
    }

    private func updateDuration() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        elapsedTime = recorder.currentTime

        if elapsedTime >= Self.maxDuration {
            try? stopRecording()
        }
    }
}

// MARK: - RecordingError

enum RecordingError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .couldNotStart:
            return "Could not start the audio recorder. Please check microphone permissions."
        }
    }
}

// MARK: - Document Picker

/// A `UIViewControllerRepresentable` wrapper for importing audio files.
struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
