import SwiftUI

/// Experimental view for AI voice cloning.
///
/// Provides a multi-step workflow: record voice samples, train the model,
/// then synthesize speech from text input.
struct VoiceCloningView: View {
    @StateObject private var service = VoiceCloningService()

    @State private var synthesisText = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showResetConfirmation = false
    @State private var isSynthesizing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                samplesSection
                trainingSection
                synthesisSection
                resultsSection
            }
            .padding()
        }
        .navigationTitle("Voice Cloning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !service.samples.isEmpty {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Reset Voice Model?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                service.removeAllSamples()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all voice samples and the trained model. This cannot be undone.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .indigo.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "waveform.and.person.filled")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("AI Voice Cloning")
                .font(.title3.weight(.bold))

            Text("Record \(VoiceCloningService.minimumSamples)+ voice samples to train a personalized voice model. Then type any text and hear it spoken in your voice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Progress indicator
            HStack(spacing: 20) {
                stepIndicator(step: 1, label: "Record", isActive: true, isComplete: service.samples.count >= VoiceCloningService.minimumSamples)
                stepConnector(isComplete: service.samples.count >= VoiceCloningService.minimumSamples)
                stepIndicator(step: 2, label: "Train", isActive: service.canTrain, isComplete: service.modelState.isReady)
                stepConnector(isComplete: service.modelState.isReady)
                stepIndicator(step: 3, label: "Speak", isActive: service.modelState.isReady, isComplete: !service.synthesisResults.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Step Indicators

    private func stepIndicator(step: Int, label: String, isActive: Bool, isComplete: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.purple : (isActive ? Color.purple.opacity(0.2) : Color(.tertiarySystemFill)))
                    .frame(width: 32, height: 32)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? .purple : .secondary)
                }
            }

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private func stepConnector(isComplete: Bool) -> some View {
        Rectangle()
            .fill(isComplete ? Color.purple : Color(.tertiarySystemFill))
            .frame(height: 2)
            .frame(maxWidth: 40)
            .padding(.bottom, 18) // Align with circles
    }

    // MARK: - Samples Section

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Voice Samples")
                    .font(.headline)

                Spacer()

                Text("\(service.samples.count)/\(VoiceCloningService.maximumSamples)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Recording button / level meter
            recordingArea

            // Sample list
            if !service.samples.isEmpty {
                VStack(spacing: 8) {
                    ForEach(service.samples) { sample in
                        sampleRow(sample)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var recordingArea: some View {
        VStack(spacing: 12) {
            // Level meter
            if service.isRecording {
                levelMeterBar
            }

            // Record button
            Button {
                handleRecordToggle()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(service.isRecording ? .red : .red.opacity(0.85))
                            .frame(width: 44, height: 44)

                        if service.isRecording {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white)
                                .frame(width: 16, height: 16)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 18, height: 18)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.isRecording ? "Stop Recording" : "Record Sample")
                            .font(.subheadline.weight(.semibold))
                        Text(service.isRecording ? "Tap to stop" : "~\(Int(VoiceCloningService.recommendedSampleDuration))s recommended")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .disabled(service.isSampleLimitReached && !service.isRecording)
        }
    }

    private var levelMeterBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(service.recordingLevel))
                    .animation(.easeOut(duration: 0.05), value: service.recordingLevel)
            }
        }
        .frame(height: 8)
    }

    private func sampleRow(_ sample: VoiceSample) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(sample.label)
                    .font(.subheadline)
                Text(formatDuration(sample.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                withAnimation {
                    service.removeSample(sample)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Training Section

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Training")
                .font(.headline)

            switch service.modelState {
            case .untrained:
                if service.canTrain {
                    trainButton
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Record at least \(VoiceCloningService.minimumSamples) samples to begin training.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

            case .training(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(.purple)

                    Text("Training model... \(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

            case .ready:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Model trained and ready")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                trainButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var trainButton: some View {
        Button {
            Task {
                await service.trainModel()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                Text("Train Voice Model")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .controlSize(.large)
        .disabled(!service.canTrain)
    }

    // MARK: - Synthesis Section

    private var synthesisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate Speech")
                .font(.headline)

            if service.modelState.isReady {
                VStack(spacing: 12) {
                    TextField("Type something to say...", text: $synthesisText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    Button {
                        handleSynthesize()
                    } label: {
                        HStack(spacing: 8) {
                            if isSynthesizing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isSynthesizing ? "Generating..." : "Generate Speech")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.large)
                    .disabled(synthesisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSynthesizing)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Train your voice model first to unlock speech generation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if !service.synthesisResults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generated Audio")
                    .font(.headline)

                ForEach(service.synthesisResults) { result in
                    resultRow(result)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func resultRow(_ result: SynthesisResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\"\(result.inputText)\"")
                .font(.subheadline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(formatDuration(result.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(result.generatedAt.formatted(date: .omitted, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Placeholder play button (audio is silent stub)
                Button {
                    // Stub: would play the generated audio
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Actions

    private func handleRecordToggle() {
        if service.isRecording {
            service.stopRecording()
        } else {
            do {
                try service.startRecording()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleSynthesize() {
        isSynthesizing = true
        Task {
            do {
                _ = try await service.synthesize(text: synthesisText)
                synthesisText = ""
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSynthesizing = false
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
