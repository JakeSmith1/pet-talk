import SwiftUI
import AVKit
import Photos

// MARK: - Export & Share View (Step 4)

struct ExportShareView: View {
    @EnvironmentObject private var project: PetTalkProject

    @State private var exportProgress: Double = 0
    @State private var isExporting: Bool = false
    @State private var exportedURL: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var savedToCameraRoll: Bool = false
    @State private var showExportOptions: Bool = false
    @State private var exportAttempted: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            if isExporting {
                exportingView
            } else if let url = exportedURL {
                completedView(url: url)
            } else {
                // Fallback – should not normally appear since export starts on appear.
                Text("Preparing export…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startExportIfNeeded)
        .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }

    // MARK: - Sub-views

    private var exportingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(value: exportProgress, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)

            Text("Exporting… \(Int(exportProgress * 100))%")
                .font(.headline)
                .monospacedDigit()

            Spacer()
        }
    }

    private func completedView(url: URL) -> some View {
        VStack(spacing: 20) {
            // Video preview
            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .onAppear {
                        player.play()
                    }
            }

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    saveToCameraRoll(url: url)
                } label: {
                    Label(
                        savedToCameraRoll ? "Saved!" : "Save to Camera Roll",
                        systemImage: savedToCameraRoll ? "checkmark.circle.fill" : "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(savedToCameraRoll)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showExportOptions = true
                } label: {
                    Label("More Export Options", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                Button(role: .destructive) {
                    project.reset()
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView(onDismiss: { showExportOptions = false })
                .environmentObject(project)
        }
    }

    // MARK: - Actions

    private func startExportIfNeeded() {
        guard !isExporting, exportedURL == nil, !exportAttempted else { return }
        isExporting = true
        exportAttempted = true

        guard let image = project.image,
              let mouthRegion = project.mouthRegion,
              let audioURL = project.mixedAudioURL ?? project.processedAudioURL ?? project.audioURL else {
            isExporting = false
            errorMessage = "Missing required project data. Please go back and complete all steps."
            showError = true
            return
        }

        exportProgress = 0

        Task {
            do {
                // Build visual effects configuration.
                var effectsConfig = VideoExporter.VisualEffectsConfig()
                effectsConfig.filter = project.selectedFilter
                effectsConfig.enableEyeAnimation = project.enableEyeAnimation
                effectsConfig.eyeRegion = project.eyeRegion
                effectsConfig.accessories = project.selectedAccessories
                effectsConfig.selectedBackground = project.selectedBackground
                effectsConfig.customBackgroundImage = project.customBackgroundImage

                // Generate eye keyframes if eye animation is enabled.
                if project.enableEyeAnimation {
                    effectsConfig.eyeKeyframes = EyeAnimatorService.generateKeyframes(
                        amplitudes: project.amplitudes
                    )
                }

                // Generate foreground mask if background replacement is active.
                if project.selectedBackground != nil || project.customBackgroundImage != nil,
                   let cgImage = image.cgImage {
                    effectsConfig.foregroundMask = try? await BackgroundRemover.generateForegroundMask(from: cgImage)
                }

                let url = try await VideoExporter.export(
                    image: image,
                    mouthRegion: mouthRegion,
                    audioURL: audioURL,
                    amplitudes: project.amplitudes,
                    effects: effectsConfig,
                    progressHandler: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    exportedURL = url
                    project.exportedVideoURL = url
                    player = AVPlayer(url: url)
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func saveToCameraRoll(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    errorMessage = "Photo library access is required to save the video."
                    showError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        savedToCameraRoll = true
                    } else {
                        errorMessage = error?.localizedDescription ?? "Failed to save video."
                        showError = true
                    }
                }
            }
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct ExportShareView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ExportShareView()
                .environmentObject(PetTalkProject())
        }
    }
}
