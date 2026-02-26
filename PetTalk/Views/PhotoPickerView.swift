import PhotosUI
import SwiftUI
import Vision

// MARK: - PhotoPickerView

struct PhotoPickerView: View {
    @EnvironmentObject private var project: PetTalkProject

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var detectedRegion: MouthRegion?
    @State private var autoDetectedRegion: MouthRegion?
    @State private var isDetecting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showCamera = false
    @State private var showMouthEditor = false

    var body: some View {
        VStack(spacing: 24) {
            if let previewImage {
                imagePreview(previewImage)
            } else {
                placeholderView
            }

            actionButtons

            if isDetecting {
                ProgressView("Detecting pet...")
                    .padding()
            }

            if previewImage != nil && detectedRegion != nil {
                HStack(spacing: 12) {
                    Button {
                        showMouthEditor = true
                    } label: {
                        Label("Adjust Mouth", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    confirmButton
                }
            }
        }
        .padding()
        .alert("Detection Failed", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onChange(of: selectedItem) { _ in
            Task {
                await handlePickerSelection()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                Task {
                    await processImage(image)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMouthEditor) {
            if let image = previewImage, let auto = autoDetectedRegion {
                NavigationStack {
                    MouthRegionEditorView(
                        image: image,
                        autoDetectedRegion: auto,
                        region: Binding(
                            get: { detectedRegion ?? auto },
                            set: { detectedRegion = $0 }
                        )
                    )
                    .padding()
                    .navigationTitle("Adjust Mouth Region")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showMouthEditor = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.large])
                .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Subviews

    private func imagePreview(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            let size = imageFittingSize(for: image, in: geometry.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                if let region = detectedRegion {
                    mouthOverlay(region: region, in: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(previewImage.map { $0.size.width / $0.size.height } ?? 1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mouthOverlay(region: MouthRegion, in size: CGSize) -> some View {
        // Vision coordinates have origin at bottom-left; SwiftUI at top-left.
        let displayCenter = CGPoint(
            x: region.center.x * size.width,
            y: (1 - region.center.y) * size.height
        )
        let displayRadius = region.radius * min(size.width, size.height)

        return Circle()
            .stroke(Color.green, lineWidth: 2)
            .fill(Color.green.opacity(0.2))
            .frame(width: displayRadius * 2, height: displayRadius * 2)
            .position(displayCenter)
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a photo of your pet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var confirmButton: some View {
        Button {
            guard let image = previewImage, let region = detectedRegion else { return }
            project.image = image
            project.mouthRegion = region
            project.currentStep = .recordAudio
        } label: {
            Text("Use This Photo")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // Extracted as a computed property so it is reusable within the HStack layout.

    // MARK: - Logic

    private func handlePickerSelection() async {
        guard let item = selectedItem else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                showError("Could not load the selected image.")
                return
            }
            await processImage(uiImage)
        } catch {
            showError("Failed to load image: \(error.localizedDescription)")
        }
    }

    private func processImage(_ image: UIImage) async {
        previewImage = image
        detectedRegion = nil
        autoDetectedRegion = nil
        isDetecting = true
        defer { isDetecting = false }

        guard let cgImage = image.cgImage else {
            showError("Could not process the image format.")
            return
        }

        do {
            let region = try await PetDetectionService.detectMouthRegion(in: cgImage)
            detectedRegion = region
            autoDetectedRegion = region
        } catch {
            showError("Please pick a photo with a clearly visible cat or dog. (\(error.localizedDescription))")
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    // MARK: - Helpers

    private func imageFittingSize(for image: UIImage, in containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }
}

// MARK: - CameraView (UIImagePickerController wrapper)

private struct CameraView: UIViewControllerRepresentable {
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
