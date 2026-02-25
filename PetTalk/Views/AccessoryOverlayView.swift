import SwiftUI

// MARK: - Accessory Overlay View

/// Positions selected accessories relative to the mouth/face region.
/// Supports drag-to-reposition, pinch-to-resize, and amplitude-driven bobble.
struct AccessoryOverlayView: View {
    @Binding var placements: [AccessoryPlacement]
    let mouthRegion: MouthRegion
    let imageSize: CGSize
    let amplitude: Float

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            ForEach(Array(placements.enumerated()), id: \.element.id) { index, placement in
                AccessoryItemView(
                    placement: $placements[index],
                    containerSize: containerSize,
                    anchorPoint: anchorPoint(for: placement.accessory, in: containerSize),
                    amplitude: amplitude
                )
            }
        }
    }

    // MARK: - Anchor Calculation

    /// Converts an accessory's default anchor preset into a point in the container's coordinate space.
    private func anchorPoint(for accessory: Accessory, in containerSize: CGSize) -> CGPoint {
        // Vision coordinates: origin bottom-left. SwiftUI: origin top-left.
        // Convert mouth center to SwiftUI space.
        let mouthX = mouthRegion.center.x * containerSize.width
        let mouthY = (1 - mouthRegion.center.y) * containerSize.height
        let radius = mouthRegion.radius * min(containerSize.width, containerSize.height)

        switch accessory.defaultAnchor {
        case .topHead:
            return CGPoint(x: mouthX, y: mouthY - radius * 6)
        case .eyes:
            return CGPoint(x: mouthX, y: mouthY - radius * 3)
        case .nose:
            return CGPoint(x: mouthX, y: mouthY - radius * 1.5)
        case .belowMouth:
            return CGPoint(x: mouthX, y: mouthY + radius * 2.5)
        case .center:
            return CGPoint(x: mouthX, y: mouthY - radius * 1.5)
        }
    }
}

// MARK: - Single Accessory Item

private struct AccessoryItemView: View {
    @Binding var placement: AccessoryPlacement
    let containerSize: CGSize
    let anchorPoint: CGPoint
    let amplitude: Float

    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0

    var body: some View {
        let bobbleOffset = CGFloat(amplitude) * 3.0

        Image(systemName: placement.accessory.sfSymbol)
            .font(.system(size: 40 * placement.scale * currentScale))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            .position(
                x: anchorPoint.x + placement.offset.width + dragOffset.width,
                y: anchorPoint.y + placement.offset.height + dragOffset.height - bobbleOffset
            )
            .gesture(dragGesture)
            .gesture(magnificationGesture)
            .animation(.easeOut(duration: 0.08), value: bobbleOffset)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                placement.offset = CGSize(
                    width: placement.offset.width + value.translation.width,
                    height: placement.offset.height + value.translation.height
                )
                dragOffset = .zero
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                currentScale = value.magnification
            }
            .onEnded { value in
                placement.scale = max(0.3, min(placement.scale * value.magnification, 4.0))
                currentScale = 1.0
            }
    }
}
