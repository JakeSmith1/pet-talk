import SwiftUI

// MARK: - Export Options View

/// Format picker allowing users to choose between Video, GIF, and Sticker Pack exports
/// with per-format configuration options.
struct ExportOptionsView: View {
    @EnvironmentObject private var project: PetTalkProject

    @State private var selectedFormat: ExportFormat = .video
    @State private var gifConfig = GIFConfiguration.default
    @State private var stickerStyle = StickerStyle.default
    @State private var stickerCount: Int = StickerPackExporter.defaultStickerCount

    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportedGIFURL: URL?
    @State private var exportedStickerPack: StickerPack?
    @State private var exportedStickerURLs: [URL] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                // Format picker
                formatPickerSection

                // Format-specific options
                switch selectedFormat {
                case .video:
                    videoOptionsSection
                case .gif:
                    gifOptionsSection
                case .stickerPack:
                    stickerOptionsSection
                }

                // Export button
                if !isExporting {
                    exportSection
                }

                // Progress section
                if isExporting {
                    progressSection
                }

                // Results section
                resultsSection
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: shareItems)
            }
        }
    }

    // MARK: - Format Picker

    private var formatPickerSection: some View {
        Section {
            Picker("Export Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Label(format.displayName, systemImage: format.icon)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.vertical, 8)
        } header: {
            Text("Format")
        } footer: {
            Text(selectedFormat.description)
        }
    }

    // MARK: - Video Options

    private var videoOptionsSection: some View {
        Section("Video Options") {
            LabeledContent("Resolution", value: "1080 x 1080")
            LabeledContent("Codec", value: "H.264")
            LabeledContent("Frame Rate", value: "30 fps")
        }
    }

    // MARK: - GIF Options

    private var gifOptionsSection: some View {
        Section("GIF Options") {
            // FPS
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Frame Rate")
                    Spacer()
                    Text("\(Int(gifConfig.fps)) fps")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $gifConfig.fps, in: 5...15, step: 1)
            }

            // Max dimension
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Size")
                    Spacer()
                    Text("\(Int(gifConfig.maxDimension))px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $gifConfig.maxDimension, in: 240...640, step: 40)
            }

            // Quality
            Picker("Quality", selection: $gifConfig.quality) {
                Text("Low (smaller file)").tag(Float(0.5))
                Text("Medium").tag(Float(0.7))
                Text("High (larger file)").tag(Float(1.0))
            }

            // Loop count
            Toggle("Loop Forever", isOn: Binding(
                get: { gifConfig.loopCount == 0 },
                set: { gifConfig.loopCount = $0 ? 0 : 1 }
            ))

            // Presets
            HStack {
                Text("Presets")
                Spacer()
                Button("Compact") {
                    gifConfig = .compact
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Default") {
                    gifConfig = .default
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("High Quality") {
                    gifConfig = .highQuality
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Sticker Options

    private var stickerOptionsSection: some View {
        Section("Sticker Pack Options") {
            // Sticker count
            Stepper("Stickers: \(stickerCount)", value: $stickerCount, in: 3...12)

            // Circular crop toggle
            Toggle("Circular Crop", isOn: $stickerStyle.circularCrop)

            // Border toggle
            Toggle("White Border", isOn: $stickerStyle.addBorder)

            // Output size
            Picker("Sticker Size", selection: $stickerStyle.outputSize) {
                Text("256px").tag(CGSize(width: 256, height: 256))
                Text("512px").tag(CGSize(width: 512, height: 512))
                Text("1024px").tag(CGSize(width: 1024, height: 1024))
            }

            // Padding
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Face Padding")
                    Spacer()
                    Text("\(Int(stickerStyle.padding * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $stickerStyle.padding, in: 0...0.5, step: 0.05)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                startExport()
            } label: {
                Label("Export \(selectedFormat.displayName)", systemImage: selectedFormat.icon)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(!canExport)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        Section {
            VStack(spacing: 8) {
                ProgressView(value: exportProgress, total: 1.0)
                    .progressViewStyle(.linear)

                Text("Exporting \(selectedFormat.displayName)... \(Int(exportProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if let gifURL = exportedGIFURL, selectedFormat == .gif {
            Section("Exported GIF") {
                Button {
                    shareItems = [gifURL]
                    showShareSheet = true
                } label: {
                    Label("Share GIF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

        if let pack = exportedStickerPack, selectedFormat == .stickerPack {
            Section("Sticker Preview") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(pack.stickers) { sticker in
                            VStack(spacing: 4) {
                                Image(uiImage: sticker.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(sticker.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if !exportedStickerURLs.isEmpty {
                    Button {
                        shareItems = exportedStickerURLs.map { $0 as Any }
                        showShareSheet = true
                    } label: {
                        Label("Share Stickers (\(exportedStickerURLs.count) PNGs)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    // MARK: - State

    private var canExport: Bool {
        project.image != nil &&
        project.mouthRegion != nil &&
        !project.amplitudes.isEmpty
    }

    // MARK: - Actions

    private func startExport() {
        guard !isExporting else { return }
        isExporting = true
        exportProgress = 0
        exportedGIFURL = nil
        exportedStickerPack = nil
        exportedStickerURLs = []

        Task {
            do {
                switch selectedFormat {
                case .video:
                    // Handled by the normal ExportShareView flow.
                    // Dismiss the sheet first, then navigate.
                    onDismiss()
                    project.currentStep = .export
                    isExporting = false

                case .gif:
                    try await exportGIF()

                case .stickerPack:
                    try await exportStickers()
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

    @MainActor
    private func exportGIF() async throws {
        guard let image = project.image,
              let mouthRegion = project.mouthRegion else {
            throw GIFExportError.failedToCreateImageFromFrame
        }

        let url = try await GIFExporter.exportGIF(
            image: image,
            mouthRegion: mouthRegion,
            amplitudes: project.amplitudes,
            configuration: gifConfig,
            progressHandler: { progress in
                exportProgress = progress
            }
        )

        exportedGIFURL = url
        isExporting = false
    }

    @MainActor
    private func exportStickers() async throws {
        guard let image = project.image,
              let mouthRegion = project.mouthRegion else {
            throw StickerExportError.faceCropFailed
        }

        let pack = try await StickerPackExporter.extractStickerPack(
            image: image,
            mouthRegion: mouthRegion,
            amplitudes: project.amplitudes,
            style: stickerStyle,
            stickerCount: stickerCount,
            progressHandler: { progress in
                exportProgress = progress * 0.8
            }
        )

        exportedStickerPack = pack

        let urls = try StickerPackExporter.exportAsPNGs(
            pack: pack,
            progressHandler: { progress in
                exportProgress = 0.8 + progress * 0.2
            }
        )

        exportedStickerURLs = urls
        isExporting = false
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case video
    case gif
    case stickerPack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .gif: return "GIF"
        case .stickerPack: return "Sticker Pack"
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .gif: return "photo.on.rectangle.angled"
        case .stickerPack: return "face.smiling"
        }
    }

    var description: String {
        switch self {
        case .video:
            return "Export as an MP4 video with audio. Best for sharing on social media."
        case .gif:
            return "Export as an animated GIF (no audio). Great for messaging and reactions."
        case .stickerPack:
            return "Extract key frames as individual PNG stickers cropped to your pet's face."
        }
    }
}

// MARK: - Preview

struct ExportOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ExportOptionsView(onDismiss: {})
            .environmentObject(PetTalkProject())
    }
}
