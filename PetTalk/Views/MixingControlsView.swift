import SwiftUI

/// Inline controls for toggling background music, selecting a track,
/// and adjusting voice/music volume levels. Embedded in PreviewView.
struct MixingControlsView: View {
    @EnvironmentObject private var project: PetTalkProject
    @ObservedObject var mixer: AudioMixer

    @Binding var showMusicPicker: Bool

    var body: some View {
        VStack(spacing: 14) {
            sectionHeader

            if mixer.isMusicEnabled {
                trackSelector
                volumeSliders
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section Header with Toggle

    private var sectionHeader: some View {
        HStack {
            Label("Background Music", systemImage: "music.note.list")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Toggle("", isOn: $mixer.isMusicEnabled)
                .labelsHidden()
                .onChange(of: mixer.isMusicEnabled) { _, enabled in
                    project.backgroundMusicURL = enabled ? mixer.backgroundMusicURL : nil
                }
        }
    }

    // MARK: - Track Selector

    private var trackSelector: some View {
        Button {
            showMusicPicker = true
        } label: {
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(.blue)

                if let url = mixer.backgroundMusicURL {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                } else {
                    Text("Choose a track...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Volume Sliders

    private var volumeSliders: some View {
        VStack(spacing: 10) {
            volumeRow(
                label: "Voice",
                systemImage: "mic.fill",
                value: $mixer.voiceVolume,
                tint: .blue
            )

            volumeRow(
                label: "Music",
                systemImage: "music.note",
                value: $mixer.musicVolume,
                tint: .purple
            )
        }
    }

    private func volumeRow(
        label: String,
        systemImage: String,
        value: Binding<Float>,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Slider(value: value, in: 0...1, step: 0.05)
                .tint(tint)
                .onChange(of: value.wrappedValue) { _, _ in
                    mixer.setVolumes(voice: mixer.voiceVolume, music: mixer.musicVolume)
                    project.voiceVolume = mixer.voiceVolume
                    project.musicVolume = mixer.musicVolume
                }

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    MixingControlsView(
        mixer: AudioMixer(),
        showMusicPicker: .constant(false)
    )
    .environmentObject(PetTalkProject())
    .padding()
}
