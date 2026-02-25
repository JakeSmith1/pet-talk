import CoreGraphics
import CoreVideo
import SpriteKit
import SwiftUI

// MARK: - Constants

private enum WarpConstants {
    static let gridColumns = 12
    static let gridRows = 12
    /// Maximum vertical displacement in normalized sprite coordinates.
    static let maxDisplacement: Float = 0.08
}

// MARK: - MouthAnimatorView

/// A SwiftUI view that wraps an `SKView` to display a pet photo with real-time
/// mouth warp animation driven by audio amplitude.
struct MouthAnimatorView: UIViewRepresentable {
    let image: UIImage
    let mouthRegion: MouthRegion
    let amplitude: Float

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.allowsTransparency = false
        skView.ignoresSiblingOrder = true

        let sceneSize = skView.bounds.size.width > 0 ? skView.bounds.size : CGSize(width: 300, height: 300)
        let scene = MouthAnimatorScene(image: image, size: sceneSize)
        scene.scaleMode = .resizeFill
        context.coordinator.scene = scene
        skView.presentScene(scene)

        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        // If the image changed, rebuild the scene.
        if context.coordinator.currentImage !== image {
            let newScene = MouthAnimatorScene(image: image, size: skView.bounds.size)
            newScene.scaleMode = .resizeFill
            context.coordinator.scene = newScene
            context.coordinator.currentImage = image
            skView.presentScene(newScene)
            newScene.updateWarp(amplitude: amplitude, mouthRegion: mouthRegion)
        } else {
            scene.updateWarp(amplitude: amplitude, mouthRegion: mouthRegion)
        }
    }

    // MARK: Coordinator

    final class Coordinator {
        var scene: MouthAnimatorScene?
        var currentImage: UIImage?
    }
}

// MARK: - MouthAnimatorScene

/// A SpriteKit scene that displays a pet image and applies warp-geometry
/// deformation to simulate mouth movement.
final class MouthAnimatorScene: SKScene {

    private var spriteNode: SKSpriteNode?

    /// Cached identity (rest) positions for all warp grid control points.
    private let identityPositions: [SIMD2<Float>]

    private let columns = WarpConstants.gridColumns
    private let rows = WarpConstants.gridRows

    // MARK: - Initialisation

    init(image: UIImage, size: CGSize) {
        // Pre-compute identity grid positions once.
        let pointsPerRow = columns + 1
        let pointsPerCol = rows + 1
        var positions = [SIMD2<Float>]()
        positions.reserveCapacity(pointsPerRow * pointsPerCol)
        for row in 0..<pointsPerCol {
            for col in 0..<pointsPerRow {
                let x = Float(col) / Float(columns)
                let y = Float(row) / Float(rows)
                positions.append(SIMD2<Float>(x, y))
            }
        }
        self.identityPositions = positions

        super.init(size: size)
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.backgroundColor = .black
        configureSpriteNode(image: image)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Sprite Setup

    private func configureSpriteNode(image: UIImage) {
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)

        // Scale to fill the scene while maintaining aspect ratio.
        let imageSize = image.size
        let scaleX = size.width / imageSize.width
        let scaleY = size.height / imageSize.height
        let fillScale = max(scaleX, scaleY)
        sprite.size = CGSize(
            width: imageSize.width * fillScale,
            height: imageSize.height * fillScale
        )

        // Enable subdivision for warp geometry.
        sprite.subdivisionLevels = 2

        addChild(sprite)
        self.spriteNode = sprite
    }

    // MARK: - Warp

    /// Updates the warp geometry to open or close the mouth.
    ///
    /// - Parameters:
    ///   - amplitude: A value in `0...1` representing how open the mouth should be.
    ///   - mouthRegion: The detected mouth region in normalised image coordinates.
    func updateWarp(amplitude: Float, mouthRegion: MouthRegion) {
        guard let sprite = spriteNode else { return }

        let clampedAmplitude = min(max(amplitude, 0), 1)
        let displacement = clampedAmplitude * WarpConstants.maxDisplacement

        let cx = Float(mouthRegion.center.x)
        let cy = Float(mouthRegion.center.y)
        let r = Float(mouthRegion.radius)

        // Guard against a zero-radius region to avoid division by zero.
        guard r > .ulpOfOne else { return }

        var warpedPositions = identityPositions

        let pointsPerRow = columns + 1

        for row in 0...(rows) {
            for col in 0...(columns) {
                let index = row * pointsPerRow + col
                let point = identityPositions[index]

                let dx = point.x - cx
                let dy = point.y - cy
                let distance = sqrt(dx * dx + dy * dy)

                guard distance < r else { continue }

                // Smooth falloff: 1 at center, 0 at the edge of the radius.
                let falloff = 1.0 - (distance / r)
                let smoothFalloff = falloff * falloff * (3.0 - 2.0 * falloff) // smoothstep

                if point.y > cy {
                    // Points above mouth center: pull upward (slight lift for upper lip).
                    let lift = displacement * 0.3 * smoothFalloff
                    warpedPositions[index].y = point.y + lift
                } else {
                    // Points below mouth center: pull downward (jaw opening).
                    let drop = displacement * smoothFalloff
                    warpedPositions[index].y = point.y - drop
                }
            }
        }

        let newGrid = SKWarpGeometryGrid(
            columns: columns,
            rows: rows,
            sourcePositions: identityPositions,
            destinationPositions: warpedPositions
        )

        sprite.warpGeometry = newGrid
    }
}

// MARK: - MouthAnimatorRenderer

/// Provides offline (non-real-time) rendering of a single warped frame,
/// returning a `CVPixelBuffer` suitable for video export.
enum MouthAnimatorRenderer {

    /// Renders a single animation frame with the given parameters.
    ///
    /// - Parameters:
    ///   - image: The pet photo to render.
    ///   - mouthRegion: The detected mouth region in normalised coordinates.
    ///   - amplitude: Mouth openness in `0...1`.
    ///   - size: The desired output size in points.
    /// - Returns: A `CVPixelBuffer` containing the rendered frame, or `nil` on failure.
    static func renderFrame(
        image: UIImage,
        mouthRegion: MouthRegion,
        amplitude: Float,
        size: CGSize
    ) -> CVPixelBuffer? {
        // Create an offscreen SpriteKit view and scene.
        let skView = SKView(frame: CGRect(origin: .zero, size: size))
        skView.allowsTransparency = false

        let scene = MouthAnimatorScene(image: image, size: size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        // Apply the warp deformation.
        scene.updateWarp(amplitude: amplitude, mouthRegion: mouthRegion)

        // Force a render pass so the warp is applied before capturing.
        // SKView needs at least one frame to process geometry changes.
        let renderer = skView

        // Render the scene to an SKTexture, then to a CGImage.
        guard let texture = renderer.texture(from: scene) else {
            return nil
        }
        let cgImage = texture.cgImage()

        return pixelBuffer(from: cgImage, size: size)
    }

    // MARK: - Pixel Buffer Conversion

    /// Draws a `CGImage` into a new `CVPixelBuffer` of the requested size.
    private static func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                        CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
