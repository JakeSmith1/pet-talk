import SwiftUI

/// An interactive editor for fine-tuning the detected mouth region overlay.
/// Supports drag to reposition and pinch to resize, with a reset button to
/// return to the auto-detected values.
struct MouthRegionEditorView: View {
    let image: UIImage
    /// The original auto-detected region (used by "Reset to Auto-Detected").
    let autoDetectedRegion: MouthRegion
    /// Binding to the current (possibly user-adjusted) region.
    @Binding var region: MouthRegion

    // MARK: - Gesture State

    /// Accumulated offset in normalized coordinates from drag gestures.
    @State private var dragOffset: CGSize = .zero
    /// Live drag translation (reset to zero on gesture end).
    @GestureState private var liveDrag: CGSize = .zero

    /// Accumulated scale factor from pinch gestures.
    @State private var pinchScale: CGFloat = 1.0
    /// Live pinch magnification (reset to 1 on gesture end).
    @GestureState private var livePinch: CGFloat = 1.0

    /// Whether the user has made manual adjustments.
    private var isModified: Bool {
        region != autoDetectedRegion
    }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let imageSize = imageFittingSize(for: image, in: geometry.size)
                let origin = CGPoint(
                    x: (geometry.size.width - imageSize.width) / 2,
                    y: (geometry.size.height - imageSize.height) / 2
                )

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageSize.width, height: imageSize.height)

                    mouthOverlay(imageSize: imageSize)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            instructionText

            resetButton
        }
    }

    // MARK: - Subviews

    private func mouthOverlay(imageSize: CGSize) -> some View {
        let totalDragNormX = dragOffset.width + liveDrag.width
        let totalDragNormY = dragOffset.height + liveDrag.height

        let currentCenter = CGPoint(
            x: region.center.x + totalDragNormX,
            y: region.center.y - totalDragNormY // Vision y is flipped
        )

        let totalScale = pinchScale * livePinch
        let currentRadius = region.radius * totalScale

        // Convert from Vision normalized coordinates to display coordinates.
        let displayCenter = CGPoint(
            x: currentCenter.x * imageSize.width,
            y: (1 - currentCenter.y) * imageSize.height
        )
        let displayRadius = currentRadius * min(imageSize.width, imageSize.height)

        let dragGesture = DragGesture()
            .updating($liveDrag) { value, state, _ in
                // Convert pixel translation to normalized coordinates.
                state = CGSize(
                    width: value.translation.width / imageSize.width,
                    height: value.translation.height / imageSize.height
                )
            }
            .onEnded { value in
                let normDX = value.translation.width / imageSize.width
                let normDY = value.translation.height / imageSize.height
                dragOffset.width += normDX
                dragOffset.height += normDY
                commitAdjustments(imageSize: imageSize)
            }

        let pinchGesture = MagnifyGesture()
            .updating($livePinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                pinchScale *= value.magnification
                commitAdjustments(imageSize: imageSize)
            }

        return ZStack {
            // Dimmed overlay outside the circle.
            Circle()
                .stroke(Color.green, lineWidth: 2.5)
                .fill(Color.green.opacity(0.15))
                .frame(width: displayRadius * 2, height: displayRadius * 2)
                .position(displayCenter)
                .shadow(color: .green.opacity(0.4), radius: 4)

            // Center crosshair for precision.
            Group {
                Rectangle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: 1, height: max(8, displayRadius * 0.5))
                Rectangle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: max(8, displayRadius * 0.5), height: 1)
            }
            .position(displayCenter)

            // Handle dot at the edge for visual affordance.
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(
                    x: displayCenter.x + displayRadius,
                    y: displayCenter.y
                )
        }
        .gesture(dragGesture)
        .gesture(pinchGesture)
    }

    private var instructionText: some View {
        Text("Drag to reposition \u{2022} Pinch to resize")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var resetButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                region = autoDetectedRegion
                dragOffset = .zero
                pinchScale = 1.0
            }
        } label: {
            Label("Reset to Auto-Detected", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isModified)
    }

    // MARK: - Logic

    /// Commits the current gesture offsets into the region binding and resets
    /// the transient gesture state.
    private func commitAdjustments(imageSize: CGSize) {
        let totalDragNormX = dragOffset.width
        let totalDragNormY = dragOffset.height
        let totalScale = pinchScale

        let newCenter = CGPoint(
            x: clamp(region.center.x + totalDragNormX, min: 0, max: 1),
            y: clamp(region.center.y - totalDragNormY, min: 0, max: 1)
        )
        let newRadius = clamp(
            region.radius * totalScale,
            min: 0.02,
            max: 0.4
        )

        region = MouthRegion(center: newCenter, radius: newRadius)
        dragOffset = .zero
        pinchScale = 1.0
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

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}
