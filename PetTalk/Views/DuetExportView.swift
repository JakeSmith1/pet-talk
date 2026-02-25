import SwiftUI
import AVKit
import Photos

// MARK: - Duet Export View

/// Handles exporting and sharing the duet side-by-side video.
struct DuetExportView: View {
    @EnvironmentObject private var duetProject: DuetProject

    @State private var exportProgress: Double = 0
    @State private var isExporting: Bool = false
    @State private var exportedURL: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var savedToCameraRoll: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            if isExporting {
                exportingView
            } else if let url = exportedURL {
                completedView(url: url)
            } else {
                Text("Preparing duet export...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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

            Text("Exporting duet... \(Int(exportProgress * 100))%")
                .font(.headline)
                .monospacedDigit()

            Spacer()
        }
    }

    private func completedView(url: URL) -> some View {
        VStack(spacing: 20) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .onAppear {
                        player.play()
                    }
            }

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

                Button(role: .destructive) {
                    duetProject.reset()
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func startExportIfNeeded() {
        guard !isExporting, exportedURL == nil else { return }
        isExporting = true
        exportProgress = 0

        Task {
            do {
                let url = try await DuetVideoExporter.export(
                    leftTrack: duetProject.leftTrack,
                    rightTrack: duetProject.rightTrack,
                    progressHandler: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    exportedURL = url
                    duetProject.exportedVideoURL = url
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

// MARK: - Preview

struct DuetExportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DuetExportView()
                .environmentObject(DuetProject())
        }
    }
}
