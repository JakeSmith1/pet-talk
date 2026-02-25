import SwiftUI

/// Combines the waveform visualization with undo/redo/reset controls and trim time labels.
/// This view is designed to be embedded in AudioRecordView after recording completes.
struct AudioTimelineView: View {
    @ObservedObject var timeline: AudioTimeline

    var body: some View {
        VStack(spacing: 12) {
            if timeline.isAnalyzing {
                ProgressView("Generating waveform...")
                    .frame(height: 100)
            } else if timeline.waveformSamples.isEmpty {
                emptyState
            } else {
                waveformSection
                trimLabels
                controlBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: timeline.waveformSamples.count)
    }

    // MARK: - Subviews

    private var waveformSection: some View {
        WaveformView(
            samples: timeline.waveformSamples,
            trimRange: $timeline.trimRange,
            playbackPosition: timeline.playbackPosition,
            onTrimChangeStarted: {
                timeline.pushUndoState()
            },
            onTrimChangeEnded: nil
        )
        .padding(.horizontal, 4)
    }

    private var trimLabels: some View {
        HStack {
            Text(formatTime(timeline.trimStartTime))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Text(formatDuration(timeline.trimmedDuration))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Text(formatTime(timeline.trimEndTime))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    timeline.undo()
                }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
            }
            .disabled(!timeline.canUndo)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    timeline.redo()
                }
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .font(.subheadline)
            }
            .disabled(!timeline.canRedo)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    timeline.resetTrim()
                }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
            .disabled(timeline.trimRange.isFullRange)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 100)
            .overlay {
                Text("No waveform data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        let frac = Int((clamped - Double(Int(clamped))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let secs = Int(clamped)
        let frac = Int((clamped - Double(secs)) * 10)
        if secs >= 60 {
            return String(format: "%d:%02d.%ds", secs / 60, secs % 60, frac)
        }
        return String(format: "%d.%ds", secs, frac)
    }
}
