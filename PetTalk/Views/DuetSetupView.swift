import PhotosUI
import SwiftUI

// MARK: - Duet Setup View

/// Side-by-side setup interface for configuring two pet tracks in a duet.
struct DuetSetupView: View {
    @EnvironmentObject private var duetProject: DuetProject

    @State private var showingAudioPickerFor: TrackSide?
    @State private var showingDocumentPicker = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Set up both pets for the duet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Side-by-side track setup
            HStack(spacing: 12) {
                TrackSetupPanel(
                    track: duetProject.leftTrack,
                    side: .left,
                    onError: showErrorMessage
                )

                Divider()

                TrackSetupPanel(
                    track: duetProject.rightTrack,
                    side: .right,
                    onError: showErrorMessage
                )
            }

            Spacer()

            // Preview button
            if duetProject.isReadyForPreview {
                Button {
                    duetProject.currentStep = .preview
                } label: {
                    Label("Preview Duet", systemImage: "play.rectangle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Configure both pets with a photo and audio to continue")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Track Side

enum TrackSide: String {
    case left
    case right

    var label: String {
        switch self {
        case .left: return "Left Pet"
        case .right: return "Right Pet"
        }
    }

    var icon: String {
        switch self {
        case .left: return "arrow.left.circle"
        case .right: return "arrow.right.circle"
        }
    }
}

// MARK: - Track Setup Panel

/// Setup panel for a single pet track within the duet interface.
struct TrackSetupPanel: View {
    @ObservedObject var track: PetTrack
    let side: TrackSide
    let onError: (String) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isDetecting = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false
    @StateObject private var recorder = AudioRecorderModel()

    var body: some View {
        VStack(spacing: 12) {
            // Track label
            Label(side.label, systemImage: side.icon)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            // Photo section
            photoSection

            // Audio section
            audioSection

            // Pitch control
            if track.audioURL != nil {
                pitchSection
            }

            // Status indicator
            statusIndicator
        }
        .onChange(of: selectedPhotoItem) { _ in
            Task { await handlePhotoSelection() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DuetCameraView { image in
                Task { await processImage(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                track.audioURL = url
            }
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(spacing: 8) {
            if let image = track.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        if track.mouthRegion != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .background(Circle().fill(.white))
                                .padding(4)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(height: 120)
                    .overlay {
                        if isDetecting {
                            ProgressView("Detecting...")
                                .font(.caption2)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "pawprint")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("Add Photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }

            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(spacing: 8) {
            if track.audioURL != nil {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.green)
                    Text("Audio ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        track.audioURL = nil
                        track.amplitudes = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: 8) {
                    // Record button
                    Button {
                        handleRecordToggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: recorder.state == .recording ? "stop.fill" : "mic.fill")
                            Text(recorder.state == .recording ? "Stop" : "Record")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(recorder.state == .recording ? .red : nil)

                    // Import button
                    Button {
                        showDocumentPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.plus")
                            Text("Import")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Pitch Section

    private var pitchSection: some View {
        VStack(spacing: 4) {
            Text("Pitch: \(String(format: "%+.0f", track.pitchShift))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(value: $track.pitchShift, in: -12...12, step: 1)
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(track.isReady ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(track.isReady ? "Ready" : "Needs setup")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func handlePhotoSelection() async {
        guard let item = selectedPhotoItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                onError("Could not load the selected image.")
                return
            }
            await processImage(uiImage)
        } catch {
            onError("Failed to load image: \(error.localizedDescription)")
        }
    }

    private func processImage(_ image: UIImage) async {
        track.image = image
        track.mouthRegion = nil
        isDetecting = true
        defer { isDetecting = false }

        guard let cgImage = image.cgImage else {
            onError("Could not process the image format.")
            return
        }

        do {
            let region = try await PetDetectionService.detectMouthRegion(in: cgImage)
            track.mouthRegion = region
        } catch {
            onError("Pet detection failed: \(error.localizedDescription)")
        }
    }

    private func handleRecordToggle() {
        do {
            if recorder.state == .recording {
                try recorder.stopRecording()
                if let url = recorder.recordedURL {
                    track.audioURL = url
                    Task {
                        let analyzer = AudioAnalyzer()
                        try await analyzer.analyzeFile(url: url)
                        await MainActor.run {
                            track.amplitudes = analyzer.amplitudes
                        }
                    }
                }
            } else {
                try recorder.startRecording()
            }
        } catch {
            onError("Recording error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Camera View for Duet

private struct DuetCameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Preview

struct DuetSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DuetSetupView()
                .environmentObject(DuetProject())
        }
    }
}
