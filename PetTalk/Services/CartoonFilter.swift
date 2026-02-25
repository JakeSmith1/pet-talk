import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Cartoon Filter Preset

/// Available CIFilter-based visual filter presets.
enum CartoonFilterPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case comicBook = "Comic Book"
    case posterize = "Posterize"
    case pixellate = "Pixellate"
    case crystallize = "Crystallize"
    case edges = "Edges"
    case noir = "Noir"

    var id: String { rawValue }

    /// SF Symbol for the filter strip thumbnail label.
    var sfSymbol: String {
        switch self {
        case .none: return "circle.slash"
        case .comicBook: return "text.bubble"
        case .posterize: return "paintpalette"
        case .pixellate: return "square.grid.3x3"
        case .crystallize: return "diamond"
        case .edges: return "pencil.and.outline"
        case .noir: return "moon.fill"
        }
    }
}

// MARK: - Cartoon Filter

/// Applies CIFilter-based cartoon/stylization effects to images and pixel buffers.
enum CartoonFilter {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Apply to UIImage

    /// Applies the selected filter preset to a UIImage.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - preset: The filter preset to apply.
    /// - Returns: The filtered UIImage, or the original if preset is `.none`.
    static func apply(to image: UIImage, preset: CartoonFilterPreset) -> UIImage {
        guard preset != .none,
              let cgImage = image.cgImage else {
            return image
        }

        let ciInput = CIImage(cgImage: cgImage)
        guard let filtered = applyFilter(to: ciInput, preset: preset),
              let outputCG = ciContext.createCGImage(filtered, from: ciInput.extent) else {
            return image
        }

        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Apply to CVPixelBuffer

    /// Applies the selected filter to a CVPixelBuffer in-place (for video export).
    ///
    /// - Parameters:
    ///   - pixelBuffer: The source pixel buffer.
    ///   - preset: The filter preset.
    /// - Returns: A new filtered CVPixelBuffer, or the original if `.none`.
    static func apply(to pixelBuffer: CVPixelBuffer, preset: CartoonFilterPreset) -> CVPixelBuffer {
        guard preset != .none else { return pixelBuffer }

        let ciInput = CIImage(cvPixelBuffer: pixelBuffer)
        guard let filtered = applyFilter(to: ciInput, preset: preset) else {
            return pixelBuffer
        }

        // Render back into the same pixel buffer.
        ciContext.render(filtered, to: pixelBuffer)
        return pixelBuffer
    }

    // MARK: - Generate Thumbnail

    /// Generates a small filtered thumbnail for the picker strip.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - preset: The filter to preview.
    ///   - thumbnailSize: Desired output size.
    /// - Returns: A filtered thumbnail UIImage.
    static func thumbnail(
        from image: UIImage,
        preset: CartoonFilterPreset,
        thumbnailSize: CGSize = CGSize(width: 60, height: 60)
    ) -> UIImage {
        // Downscale first for performance.
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let downscaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
        return apply(to: downscaled, preset: preset)
    }

    // MARK: - Core Filter Pipeline

    private static func applyFilter(to input: CIImage, preset: CartoonFilterPreset) -> CIImage? {
        switch preset {
        case .none:
            return input

        case .comicBook:
            return input.applyingFilter("CIComicEffect")

        case .posterize:
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = input
            posterize.levels = 6
            return posterize.outputImage

        case .pixellate:
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = input
            pixellate.scale = max(input.extent.width / 80, 4)
            return pixellate.outputImage

        case .crystallize:
            let crystallize = CIFilter.crystallize()
            crystallize.inputImage = input
            crystallize.radius = max(Float(input.extent.width / 60), 5)
            return crystallize.outputImage

        case .edges:
            let edges = CIFilter.edges()
            edges.inputImage = input
            edges.intensity = 5.0
            return edges.outputImage

        case .noir:
            return input.applyingFilter("CIPhotoEffectNoir")
        }
    }
}
