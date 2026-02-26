import SwiftUI

/// Step 3 of the PetTalk workflow — real-time preview of the pet's mouth animated in sync with audio.
struct PreviewView: View {
    @EnvironmentObject private var project: PetTalkProject
    @ObservedObject private var featureFlags = FeatureFlags.shared

    @StateObject private var audioAnalyzer = AudioAnalyzer()
    @StateObject private var audioMixer = AudioMixer()

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isProcessingAudio = false
    @State private var showMusicPicker = false
    @State private var lipSyncActive = false

    var body: some View {
        VStack(spacing: 24) {
            if let image = project.image,
               let mouthRegion = project.mouthRegion,
               let audioURL = project.audioURL {
                previewContent(image: image, mouthRegion: mouthRegion, audioURL: audioURL)
            } else {
                missingDataView
            }
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            preAnalyzeAudio()
        }
        .onDisappear {
            stopIfPlaying()
        }
    }

    // MARK: - Subviews

    private func previewContent(image: UIImage, mouthRegion: MouthRegion, audioURL: URL) -> some View {
        VStack(spacing: 0) {
            // Fixed animation area (outside ScrollView so gestures aren't captured by scroll)
            ZStack {
                MouthAnimatorView(
                    image: image,
                    mouthRegion: mouthRegion,
                    amplitude: audioAnalyzer.amplitude
                )

                // Eye animation overlay
                if project.enableEyeAnimation, let eyeRegion = project.eyeRegion {
                    let keyframe = currentEyeKeyframe
                    EyeAnimatorView(
                        image: image,
                        eyeRegion: eyeRegion,
                        blinkAmount: keyframe.blinkAmount,
                        eyebrowRaise: keyframe.eyebrowRaise
                    )
                    .allowsHitTesting(false)
                }

                // Accessory overlay
                if !project.selectedAccessories.isEmpty {
                    AccessoryOverlayView(
                        placements: $project.selectedAccessories,
                        mouthRegion: mouthRegion,
                        imageSize: image.size,
                        amplitude: audioAnalyzer.amplitude
                    )
                }
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Scrollable controls
            ScrollView {
                VStack(spacing: 24) {
                    playbackControls(audioURL: audioURL)

                    voiceEffectControls

                    // Visual effects panel
                    VisualEffectsView()

                    MixingControlsView(mixer: audioMixer, showMusicPicker: $showMusicPicker)

                    // Experimental features panel
                    if featureFlags.hasAnyEnabled {
                        experimentalFeaturesPanel
                    }

                    exportButton(audioURL: audioURL)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showMusicPicker) {
            MusicPickerView(mixer: audioMixer)
        }
        .task {
            await detectEyeRegionIfNeeded(image: image)
        }
    }

    /// Returns the current eye keyframe based on playback time or a static default.
    private var currentEyeKeyframe: EyeKeyframe {
        guard project.enableEyeAnimation else {
            return EyeKeyframe(blinkAmount: 0, eyebrowRaise: 0, time: 0)
        }
        let keyframes = EyeAnimatorService.generateKeyframes(amplitudes: project.amplitudes)
        guard !keyframes.isEmpty else {
            return EyeKeyframe(blinkAmount: 0, eyebrowRaise: audioAnalyzer.amplitude * 1.5, time: 0)
        }
        // Map current amplitude to nearest keyframe index.
        let frameIndex = min(
            Int(Double(audioAnalyzer.amplitude) * Double(keyframes.count)),
            keyframes.count - 1
        )
        return keyframes[max(0, frameIndex)]
    }

    /// Detects eye region for the current image if not already available.
    private func detectEyeRegionIfNeeded(image: UIImage) async {
        guard project.eyeRegion == nil, let cgImage = image.cgImage else { return }
        project.eyeRegion = await EyeAnimatorService.detectEyeRegion(in: cgImage)
    }

    private func playbackControls(audioURL: URL) -> some View {
        HStack(spacing: 20) {
            Button {
                handlePlaybackToggle(audioURL: audioURL)
            } label: {
                Image(systemName: audioAnalyzer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel(audioAnalyzer.isPlaying ? "Pause" : "Play")
        }
    }

    private var voiceEffectControls: some View {
        VStack(spacing: 12) {
            Text("Voice Effect")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(VoicePreset.allCases) { preset in
                    Button(preset.label) {
                        project.pitchShift = preset.semitones
                        audioAnalyzer.setPitch(preset.semitones)
                    }
                    .buttonStyle(.bordered)
                    .tint(project.pitchShift == preset.semitones ? .blue : .gray)
                    .controlSize(.small)
                }
            }

            HStack {
                Text("-12")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $project.pitchShift, in: -12...12, step: 0.5)
                    .onChange(of: project.pitchShift) { newValue in
                        audioAnalyzer.setPitch(newValue)
                    }
                Text("+12")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportButton(audioURL: URL) -> some View {
        Button {
            handleExport(audioURL: audioURL)
        } label: {
            if isProcessingAudio {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Export Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isProcessingAudio)
    }

    // MARK: - Experimental Features Panel

    @ViewBuilder
    private var experimentalFeaturesPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(.purple)
                Text("Experimental")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
            }

            if featureFlags.lipShapeMatching {
                HStack(spacing: 8) {
                    Image(systemName: "mouth")
                        .foregroundStyle(.pink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lip-Shape Matching")
                            .font(.subheadline.weight(.medium))
                        Text(lipSyncActive ? "Phoneme analysis active" : "Will enhance export with viseme data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                )
            }

            if featureFlags.liveCameraAR {
                NavigationLink {
                    LiveCameraView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(.cyan)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Live Camera AR")
                                .font(.subheadline.weight(.medium))
                            Text("Try real-time mouth overlay")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            if featureFlags.aiVoiceCloning {
                NavigationLink {
                    VoiceCloningView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.and.person.filled")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("AI Voice Cloning")
                                .font(.subheadline.weight(.medium))
                            Text("Generate speech with your voice")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var missingDataView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Missing project data")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Please go back and ensure you have selected a photo and recorded audio.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Actions

    private func handlePlaybackToggle(audioURL: URL) {
        if audioAnalyzer.isPlaying {
            audioAnalyzer.stopPlayback()
        } else {
            do {
                try audioAnalyzer.startPlayback(url: audioURL)
            } catch {
                errorMessage = "Playback failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func preAnalyzeAudio() {
        guard let audioURL = project.audioURL else { return }
        Task {
            do {
                try await audioAnalyzer.analyzeFile(url: audioURL)
                project.amplitudes = audioAnalyzer.amplitudes
            } catch {
                errorMessage = "Audio analysis failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func handleExport(audioURL: URL) {
        stopIfPlaying()
        audioMixer.stopPreview()

        isProcessingAudio = true
        Task {
            do {
                // Step 1: Apply pitch shift if needed
                var baseAudioURL = audioURL
                if project.pitchShift != 0 {
                    let processedURL = try await audioAnalyzer.renderProcessedAudio(
                        inputURL: audioURL,
                        pitchShift: project.pitchShift
                    )
                    project.processedAudioURL = processedURL
                    baseAudioURL = processedURL
                } else {
                    project.processedAudioURL = nil
                }

                // Step 2: Mix with background music if enabled
                if audioMixer.isMusicEnabled, let musicURL = audioMixer.backgroundMusicURL {
                    let mixedURL = try await audioMixer.mixAudio(
                        voiceURL: baseAudioURL,
                        musicURL: musicURL,
                        voiceVolume: audioMixer.voiceVolume,
                        musicVolume: audioMixer.musicVolume
                    )
                    project.mixedAudioURL = mixedURL
                    project.voiceVolume = audioMixer.voiceVolume
                    project.musicVolume = audioMixer.musicVolume
                } else {
                    project.mixedAudioURL = nil
                }

                // Step 3: Re-analyze final audio for amplitude data
                let finalAudioURL = project.mixedAudioURL ?? project.processedAudioURL ?? audioURL
                try await audioAnalyzer.analyzeFile(url: finalAudioURL)
                project.amplitudes = audioAnalyzer.amplitudes

                isProcessingAudio = false
                project.currentStep = .export
            } catch {
                isProcessingAudio = false
                errorMessage = "Audio processing failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func stopIfPlaying() {
        if audioAnalyzer.isPlaying {
            audioAnalyzer.stopPlayback()
        }
        if audioMixer.isPreviewing {
            audioMixer.stopPreview()
        }
    }
}

// MARK: - Voice Presets

private enum VoicePreset: String, CaseIterable, Identifiable {
    case original
    case chipmunk
    case deep
    case robot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .chipmunk: return "Chipmunk"
        case .deep: return "Deep"
        case .robot: return "Robot"
        }
    }

    var semitones: Float {
        switch self {
        case .original: return 0
        case .chipmunk: return 8
        case .deep: return -6
        case .robot: return -3
        }
    }
}
