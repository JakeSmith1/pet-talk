import SwiftUI

/// A polished waveform visualization with interactive trim handles and a playback position indicator.
///
/// The waveform is drawn as mirrored vertical bars. The trim region is highlighted while
/// areas outside the trim are dimmed. Trim handles can be dragged to adjust the range.
struct WaveformView: View {
    /// Normalized waveform samples (0...1).
    let samples: [Float]
    /// Current trim range (fractional 0...1).
    @Binding var trimRange: TrimRange
    /// Current playback position as a fraction of total duration (0...1).
    let playbackPosition: Double
    /// Called when a trim handle drag begins (to snapshot undo state).
    var onTrimChangeStarted: (() -> Void)?
    /// Called when a trim handle drag ends.
    var onTrimChangeEnded: (() -> Void)?

    // MARK: - Configuration

    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 2
    private let handleWidth: CGFloat = 14
    private let cornerRadius: CGFloat = 8

    // MARK: - Gesture State

    @GestureState private var dragStartHandle: Double?
    @GestureState private var dragEndHandle: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .leading) {
                // Background waveform (dimmed).
                waveformBars(in: geometry, dimmed: true)

                // Highlighted trim region.
                waveformBars(in: geometry, dimmed: false)
                    .mask(trimMask(width: width, height: height))

                // Trim region border.
                trimBorder(width: width, height: height)

                // Playback position indicator.
                playbackIndicator(width: width, height: height)

                // Draggable trim handles.
                startHandle(width: width, height: height)
                endHandle(width: width, height: height)
            }
        }
        .frame(height: 100)
    }

    // MARK: - Waveform Drawing

    private func waveformBars(in geometry: GeometryProxy, dimmed: Bool) -> some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let count = samples.count
        guard count > 0 else { return AnyView(EmptyView()) }

        let barWidth = max(1, (width - CGFloat(count - 1) * barSpacing) / CGFloat(count))
        let maxBarHeight = height * 0.45

        return AnyView(
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<count, id: \.self) { index in
                    let amplitude = CGFloat(samples[index])
                    let barHeight = max(minBarHeight, amplitude * maxBarHeight)

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(dimmed ? AnyShapeStyle(Color.secondary.opacity(0.25)) : AnyShapeStyle(barGradient(amplitude: amplitude)))
                        .frame(width: barWidth, height: barHeight * 2)
                }
            }
        )
    }

    private func barGradient(amplitude: CGFloat) -> some ShapeStyle {
        Color.accentColor.opacity(0.6 + Double(amplitude) * 0.4)
    }

    // MARK: - Trim Visualization

    private func trimMask(width: CGFloat, height: CGFloat) -> some View {
        let startX = effectiveStartFraction * width
        let endX = effectiveEndFraction * width

        return Rectangle()
            .frame(width: max(0, endX - startX))
            .offset(x: startX)
            .frame(width: width, height: height, alignment: .leading)
    }

    private func trimBorder(width: CGFloat, height: CGFloat) -> some View {
        let startX = effectiveStartFraction * width
        let endX = effectiveEndFraction * width
        let trimWidth = max(0, endX - startX)

        return RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            .frame(width: trimWidth, height: height)
            .position(x: startX + trimWidth / 2, y: height / 2)
    }

    // MARK: - Playback Indicator

    private func playbackIndicator(width: CGFloat, height: CGFloat) -> some View {
        let xPos = playbackPosition * width

        return Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: height)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            .position(x: xPos, y: height / 2)
            .animation(.linear(duration: 0.05), value: playbackPosition)
    }

    // MARK: - Trim Handles

    private func startHandle(width: CGFloat, height: CGFloat) -> some View {
        let fraction = effectiveStartFraction
        let xPos = fraction * width

        return trimHandleShape(isLeading: true)
            .frame(width: handleWidth, height: height * 0.7)
            .position(x: xPos, y: height / 2)
            .gesture(
                DragGesture()
                    .updating($dragStartHandle) { value, state, _ in
                        if state == nil {
                            onTrimChangeStarted?()
                            state = trimRange.start
                        }
                        // Intentionally empty — we use onChange to update.
                    }
                    .onChanged { value in
                        let newFraction = max(0, min(value.location.x / width, trimRange.end - 0.02))
                        trimRange.start = newFraction
                    }
                    .onEnded { _ in
                        onTrimChangeEnded?()
                    }
            )
    }

    private func endHandle(width: CGFloat, height: CGFloat) -> some View {
        let fraction = effectiveEndFraction
        let xPos = fraction * width

        return trimHandleShape(isLeading: false)
            .frame(width: handleWidth, height: height * 0.7)
            .position(x: xPos, y: height / 2)
            .gesture(
                DragGesture()
                    .updating($dragEndHandle) { value, state, _ in
                        if state == nil {
                            onTrimChangeStarted?()
                            state = trimRange.end
                        }
                    }
                    .onChanged { value in
                        let newFraction = min(1, max(value.location.x / width, trimRange.start + 0.02))
                        trimRange.end = newFraction
                    }
                    .onEnded { _ in
                        onTrimChangeEnded?()
                    }
            )
    }

    private func trimHandleShape(isLeading: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor)

            // Grip lines.
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 4, height: 1)
                }
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2)
        .contentShape(Rectangle().inset(by: -10)) // Larger hit target.
    }

    // MARK: - Computed

    private var effectiveStartFraction: Double {
        trimRange.start
    }

    private var effectiveEndFraction: Double {
        trimRange.end
    }
}
