import SwiftUI

/// A sheet that lets the user browse, preview, and select a built-in sound effect.
struct SoundEffectPickerView: View {
    @EnvironmentObject private var project: PetTalkProject
    @StateObject private var library = SoundEffectLibrary()

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: SoundEffect.Category = .bark
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker
                effectsList
            }
            .searchable(text: $searchText, prompt: "Search effects")
            .navigationTitle("Sound Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        library.stopPreview()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                library.stopPreview()
            }
        }
    }

    // MARK: - Subviews

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            ForEach(SoundEffect.Category.allCases, id: \.self) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var effectsList: some View {
        List(filteredEffects) { effect in
            SoundEffectRow(
                effect: effect,
                isPlaying: library.nowPlaying?.id == effect.id,
                onPreview: { togglePreview(effect) },
                onSelect: { selectEffect(effect) }
            )
        }
        .listStyle(.plain)
        .overlay {
            if filteredEffects.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Filtering

    private var filteredEffects: [SoundEffect] {
        let categoryEffects = SoundEffectLibrary.effects(for: selectedCategory)
        guard !searchText.isEmpty else { return categoryEffects }
        return categoryEffects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func togglePreview(_ effect: SoundEffect) {
        if library.nowPlaying?.id == effect.id {
            library.stopPreview()
        } else {
            library.previewSound(effect)
        }
    }

    private func selectEffect(_ effect: SoundEffect) {
        library.stopPreview()
        guard let url = library.urlForEffect(effect) else { return }
        project.selectedSoundEffect = effect
        project.audioURL = url
        project.currentStep = .preview
        dismiss()
    }
}

// MARK: - SoundEffectRow

/// A single row in the sound effects list showing name, duration, preview, and select controls.
private struct SoundEffectRow: View {
    let effect: SoundEffect
    let isPlaying: Bool
    let onPreview: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            previewButton

            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            selectButton
        }
        .padding(.vertical, 4)
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(isPlaying ? .red : .blue)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop Preview" : "Preview")
    }

    private var selectButton: some View {
        Button("Use This Sound", action: onSelect)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    private var formattedDuration: String {
        let seconds = Int(effect.duration)
        let tenths = Int((effect.duration - Double(seconds)) * 10)
        return "\(seconds).\(tenths)s"
    }
}
