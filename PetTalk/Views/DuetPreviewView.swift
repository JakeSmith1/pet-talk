import SwiftUI

// MARK: - Duet Preview View

/// Split-screen preview showing both pets animated independently with their own audio.
struct DuetPreviewView: View {
    @EnvironmentObject private var duetProject: DuetProject

    @StateObject private var leftAnalyzer = AudioAnalyzer()
    @StateObject private var rightAnalyzer = AudioAnalyzer()

    @State private var isPlaying = false
    @State private var isProcessingAudio = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 16) {
            // Split-screen preview
            splitScreenPreview

            // Playback controls
            playbackControls

            // Per-track pitch controls
            pitchControls

            // Export button
            exportButton
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
            stopPlayback()
        }
    }

    // MARK: - Split Screen Preview

    private var splitScreenPreview: some View {
        HStack(spacing: 4) {
            // Left pet
            petPanel(
                track: duetProject.leftTrack,
                analyzer: leftAnalyzer,
                label: "Left"
            )

            // Divider
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)

            // Right pet
            petPanel(
                track: duetProject.rightTrack,
                analyzer: rightAnalyzer,
                label: "Right"
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }

    private func petPanel(
        track: PetTrack,
        analyzer: AudioAnalyzer,
        label: String
    ) -> some View {
        ZStack(alignment: .bottom) {
            if let image = track.image, let mouthRegion = track.mouthRegion {
                MouthAnimatorView(
                    image: image,
                    mouthRegion: mouthRegion,
                    amplitude: analyzer.amplitude
                )
                .aspectRatio(1, contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color(.systemBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Text("No image")
                            .foregroundStyle(.secondary)
                    }
            }

            // Label overlay
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(6)
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 24) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
    }

    // MARK: - Pitch Controls

    private var pitchControls: some View {
        VStack(spacing: 12) {
            Text("Voice Effects")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                // Left track pitch
                VStack(spacing: 4) {
                    Text(duetProject.leftTrack.label)
                        .font(.caption.weight(.medium))
                    Text("\(String(format: "%+.0f", duetProject.leftTrack.pitchShift)) st")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Slider(value: $duetProject.leftTrack.pitchShift, in: -12...12, step: 0.5)
                        .onChange(of: duetProject.leftTrack.pitchShift) { _, newValue in
                            leftAnalyzer.setPitch(newValue)
                        }
                }

                // Right track pitch
                VStack(spacing: 4) {
                    Text(duetProject.rightTrack.label)
                        .font(.caption.weight(.medium))
                    Text("\(String(format: "%+.0f", duetProject.rightTrack.pitchShift)) st")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Slider(value: $duetProject.rightTrack.pitchShift, in: -12...12, step: 0.5)
                        .onChange(of: duetProject.rightTrack.pitchShift) { _, newValue in
                            rightAnalyzer.setPitch(newValue)
                        }
                }
            }
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            handleExport()
        } label: {
            if isProcessingAudio {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Export Duet Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isProcessingAudio)
    }

    // MARK: - Actions

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let leftAudioURL = duetProject.leftTrack.audioURL,
              let rightAudioURL = duetProject.rightTrack.audioURL else {
            errorMessage = "Audio not available for both tracks."
            showError = true
            return
        }

        do {
            try leftAnalyzer.startPlayback(url: leftAudioURL)
            try rightAnalyzer.startPlayback(url: rightAudioURL)
            isPlaying = true
        } catch {
            stopPlayback()
            errorMessage = "Playback failed: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopPlayback() {
        leftAnalyzer.stopPlayback()
        rightAnalyzer.stopPlayback()
        isPlaying = false
    }

    private func preAnalyzeAudio() {
        Task {
            do {
                if let leftURL = duetProject.leftTrack.audioURL {
                    try await leftAnalyzer.analyzeFile(url: leftURL)
                    duetProject.leftTrack.amplitudes = leftAnalyzer.amplitudes
                }
                if let rightURL = duetProject.rightTrack.audioURL {
                    try await rightAnalyzer.analyzeFile(url: rightURL)
                    duetProject.rightTrack.amplitudes = rightAnalyzer.amplitudes
                }
            } catch {
                errorMessage = "Audio analysis failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func handleExport() {
        stopPlayback()
        isProcessingAudio = true

        Task {
            do {
                // Process pitch for left track if needed
                if duetProject.leftTrack.pitchShift != 0,
                   let audioURL = duetProject.leftTrack.audioURL {
                    let processedURL = try await leftAnalyzer.renderProcessedAudio(
                        inputURL: audioURL,
                        pitchShift: duetProject.leftTrack.pitchShift
                    )
                    try await leftAnalyzer.analyzeFile(url: processedURL)
                    duetProject.leftTrack.amplitudes = leftAnalyzer.amplitudes
                    duetProject.leftTrack.processedAudioURL = processedURL
                } else {
                    duetProject.leftTrack.processedAudioURL = nil
                }

                // Process pitch for right track if needed
                if duetProject.rightTrack.pitchShift != 0,
                   let audioURL = duetProject.rightTrack.audioURL {
                    let processedURL = try await rightAnalyzer.renderProcessedAudio(
                        inputURL: audioURL,
                        pitchShift: duetProject.rightTrack.pitchShift
                    )
                    try await rightAnalyzer.analyzeFile(url: processedURL)
                    duetProject.rightTrack.amplitudes = rightAnalyzer.amplitudes
                    duetProject.rightTrack.processedAudioURL = processedURL
                } else {
                    duetProject.rightTrack.processedAudioURL = nil
                }

                isProcessingAudio = false
                duetProject.currentStep = .export
            } catch {
                isProcessingAudio = false
                errorMessage = "Audio processing failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DuetPreviewView()
            .environmentObject(DuetProject())
    }
}
