import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// A sheet that lets the user browse built-in music tracks by category,
/// preview them, or import a custom audio file from the Files app.
struct MusicPickerView: View {
    @EnvironmentObject private var project: PetTalkProject
    @ObservedObject var mixer: AudioMixer

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: MusicTrack.Category = .upbeat
    @State private var previewingTrackID: String?
    @State private var previewPlayer: AVAudioPlayer?
    @State private var showFileImporter = false
    @State private var importedTracks: [MusicTrack] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryTabs
                trackList
            }
            .navigationTitle("Choose Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopTrackPreview()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import from Files") {
                        showFileImporter = true
                    }
                    .font(.subheadline)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .onDisappear {
            stopTrackPreview()
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MusicTrack.Category.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.rawValue, systemImage: category.systemImage)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.systemGray6)
                            )
                            .foregroundStyle(
                                selectedCategory == category ? .blue : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        let categoryTracks = MusicTrack.tracks(for: selectedCategory)
        let importedForCategory = importedTracks.filter { $0.category == selectedCategory }
        let allTracks = categoryTracks + importedForCategory

        return List {
            if allTracks.isEmpty && importedForCategory.isEmpty {
                Text("No tracks in this category.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(allTracks) { track in
                trackRow(track)
            }

            // Show imported tracks in every category tab
            if !importedTracks.isEmpty && selectedCategory == .chill {
                Section("Imported") {
                    ForEach(importedTracks) { track in
                        trackRow(track)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        HStack(spacing: 12) {
            // Preview button
            Button {
                toggleTrackPreview(track)
            } label: {
                Image(systemName: previewingTrackID == track.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(previewingTrackID == track.id ? .red : .blue)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.body.weight(.medium))
                Text(formattedDuration(track.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Select button
            Button("Select") {
                selectTrack(track)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func selectTrack(_ track: MusicTrack) {
        stopTrackPreview()
        mixer.backgroundMusicURL = track.url
        mixer.isMusicEnabled = true
        project.backgroundMusicURL = track.url
        dismiss()
    }

    private func toggleTrackPreview(_ track: MusicTrack) {
        if previewingTrackID == track.id {
            stopTrackPreview()
            return
        }

        stopTrackPreview()

        guard let url = track.url else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            previewingTrackID = track.id
        } catch {
            // Track may not exist in bundle yet -- silently ignore
            previewingTrackID = nil
        }
    }

    private func stopTrackPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingTrackID = nil
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            // Copy to app's temporary directory so it persists
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)

            do {
                try FileManager.default.copyItem(at: url, to: destination)

                // Get duration
                let asset = AVURLAsset(url: destination)
                Task {
                    let duration = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    let name = url.deletingPathExtension().lastPathComponent
                    let track = MusicTrack.imported(url: destination, name: name, duration: seconds)

                    await MainActor.run {
                        importedTracks.append(track)
                        selectTrack(track)
                    }
                }
            } catch {
                // Import failed silently
            }

        case .failure:
            break
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    MusicPickerView(mixer: AudioMixer())
        .environmentObject(PetTalkProject())
}
