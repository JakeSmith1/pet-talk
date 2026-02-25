import SpriteKit
import SwiftUI

// MARK: - Constants

private enum EyeWarpConstants {
    static let gridColumns = 8
    static let gridRows = 8
    /// Maximum vertical displacement for blink (eyelid closing).
    static let maxBlinkDisplacement: Float = 0.04
    /// Maximum vertical displacement for eyebrow raise.
    static let maxBrowDisplacement: Float = 0.025
}

// MARK: - EyeAnimatorView

/// A SpriteKit-backed overlay that applies warp-geometry deformation to simulate
/// eye blinks and eyebrow raises on a pet image.
struct EyeAnimatorView: UIViewRepresentable {
    let image: UIImage
    let eyeRegion: EyeRegion
    let blinkAmount: Float
    let eyebrowRaise: Float

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.allowsTransparency = true
        skView.backgroundColor = .clear
        skView.ignoresSiblingOrder = true

        let sceneSize = skView.bounds.size.width > 0 ? skView.bounds.size : CGSize(width: 300, height: 300)
        let scene = EyeAnimatorScene(image: image, size: sceneSize)
        scene.scaleMode = .resizeFill
        context.coordinator.scene = scene
        context.coordinator.currentImage = image
        skView.presentScene(scene)

        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        if context.coordinator.currentImage !== image {
            let newScene = EyeAnimatorScene(image: image, size: skView.bounds.size)
            newScene.scaleMode = .resizeFill
            context.coordinator.scene = newScene
            context.coordinator.currentImage = image
            skView.presentScene(newScene)
            newScene.updateWarp(
                eyeRegion: eyeRegion,
                blinkAmount: blinkAmount,
                eyebrowRaise: eyebrowRaise
            )
        } else {
            scene.updateWarp(
                eyeRegion: eyeRegion,
                blinkAmount: blinkAmount,
                eyebrowRaise: eyebrowRaise
            )
        }
    }

    final class Coordinator {
        var scene: EyeAnimatorScene?
        var currentImage: UIImage?
    }
}

// MARK: - EyeAnimatorScene

/// SpriteKit scene that applies warp geometry to simulate eye blinks and eyebrow movement.
final class EyeAnimatorScene: SKScene {

    private var spriteNode: SKSpriteNode?
    private let identityPositions: [SIMD2<Float>]
    private let columns = EyeWarpConstants.gridColumns
    private let rows = EyeWarpConstants.gridRows

    init(image: UIImage, size: CGSize) {
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
        self.backgroundColor = .clear
        configureSpriteNode(image: image)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configureSpriteNode(image: UIImage) {
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        let imageSize = image.size
        let scaleX = size.width / imageSize.width
        let scaleY = size.height / imageSize.height
        let fillScale = max(scaleX, scaleY)
        sprite.size = CGSize(
            width: imageSize.width * fillScale,
            height: imageSize.height * fillScale
        )
        sprite.subdivisionLevels = 2
        sprite.alpha = 1.0
        addChild(sprite)
        self.spriteNode = sprite
    }

    /// Updates warp geometry for eye blink and eyebrow raise.
    ///
    /// - Parameters:
    ///   - eyeRegion: Detected eye locations in normalized coordinates.
    ///   - blinkAmount: 0 = open, 1 = closed.
    ///   - eyebrowRaise: 0 = neutral, 1 = fully raised.
    func updateWarp(eyeRegion: EyeRegion, blinkAmount: Float, eyebrowRaise: Float) {
        guard let sprite = spriteNode else { return }

        let clampedBlink = min(max(blinkAmount, 0), 1)
        let clampedBrow = min(max(eyebrowRaise, 0), 1)

        // If both are effectively zero, reset to identity.
        guard clampedBlink > 0.001 || clampedBrow > 0.001 else {
            let grid = SKWarpGeometryGrid(
                columns: columns,
                rows: rows,
                sourcePositions: identityPositions,
                destinationPositions: identityPositions
            )
            sprite.warpGeometry = grid
            return
        }

        let blinkDisp = clampedBlink * EyeWarpConstants.maxBlinkDisplacement
        let browDisp = clampedBrow * EyeWarpConstants.maxBrowDisplacement

        let eyes: [(cx: Float, cy: Float, r: Float)] = [
            (Float(eyeRegion.leftEyeCenter.x), Float(eyeRegion.leftEyeCenter.y), Float(eyeRegion.leftEyeRadius)),
            (Float(eyeRegion.rightEyeCenter.x), Float(eyeRegion.rightEyeCenter.y), Float(eyeRegion.rightEyeRadius)),
        ]

        // Eyebrow region is above the eye midpoint.
        let browCx = Float(eyeRegion.midpoint.x)
        let browCy = Float(eyeRegion.midpoint.y) + Float(max(eyeRegion.leftEyeRadius, eyeRegion.rightEyeRadius)) * 2.5
        let browRadius: Float = Float(hypot(
            eyeRegion.rightEyeCenter.x - eyeRegion.leftEyeCenter.x,
            eyeRegion.rightEyeCenter.y - eyeRegion.leftEyeCenter.y
        )) * 0.6

        let pointsPerRow = columns + 1
        var warpedPositions = identityPositions

        for row in 0...rows {
            for col in 0...columns {
                let index = row * pointsPerRow + col
                let point = identityPositions[index]

                // Blink: squeeze eye region vertically toward eye center.
                for eye in eyes {
                    let dx = point.x - eye.cx
                    let dy = point.y - eye.cy
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance < eye.r else { continue }

                    let falloff = 1.0 - (distance / eye.r)
                    let smooth = falloff * falloff * (3.0 - 2.0 * falloff)

                    // Pull points toward the eye center Y.
                    let verticalPull = (point.y > eye.cy) ? -blinkDisp * smooth : blinkDisp * smooth
                    warpedPositions[index].y += verticalPull
                }

                // Eyebrow raise: push upward above eyes.
                let bdx = point.x - browCx
                let bdy = point.y - browCy
                let bDist = sqrt(bdx * bdx + bdy * bdy)
                if bDist < browRadius, browRadius > .ulpOfOne {
                    let falloff = 1.0 - (bDist / browRadius)
                    let smooth = falloff * falloff * (3.0 - 2.0 * falloff)
                    warpedPositions[index].y += browDisp * smooth
                }
            }
        }

        let grid = SKWarpGeometryGrid(
            columns: columns,
            rows: rows,
            sourcePositions: identityPositions,
            destinationPositions: warpedPositions
        )
        sprite.warpGeometry = grid
    }
}

// MARK: - Offline Renderer

/// Provides offline rendering of a single eye-animated frame for video export.
enum EyeAnimatorRenderer {

    /// Renders a single frame with eye animation applied.
    ///
    /// - Parameters:
    ///   - image: The pet photo.
    ///   - eyeRegion: Detected eye region in normalized coordinates.
    ///   - blinkAmount: 0 = open, 1 = closed.
    ///   - eyebrowRaise: 0 = neutral, 1 = raised.
    ///   - size: Output size in points.
    /// - Returns: A `CVPixelBuffer`, or `nil` on failure.
    static func renderFrame(
        image: UIImage,
        eyeRegion: EyeRegion,
        blinkAmount: Float,
        eyebrowRaise: Float,
        size: CGSize
    ) -> CVPixelBuffer? {
        let skView = SKView(frame: CGRect(origin: .zero, size: size))
        skView.allowsTransparency = true

        let scene = EyeAnimatorScene(image: image, size: size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        scene.updateWarp(eyeRegion: eyeRegion, blinkAmount: blinkAmount, eyebrowRaise: eyebrowRaise)

        guard let texture = skView.texture(from: scene),
              let cgImage = texture.cgImage() else {
            return nil
        }

        return pixelBuffer(from: cgImage, size: size)
    }

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
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(
            data: baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
