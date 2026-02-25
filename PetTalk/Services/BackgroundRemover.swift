import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

// MARK: - Errors

enum BackgroundRemovalError: LocalizedError {
    case segmentationFailed
    case maskGenerationFailed
    case compositionFailed
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .segmentationFailed:
            return "Failed to segment the foreground from the background."
        case .maskGenerationFailed:
            return "Failed to generate the foreground mask."
        case .compositionFailed:
            return "Failed to composite the foreground onto the new background."
        case .imageConversionFailed:
            return "Failed to convert the image for processing."
        }
    }
}

// MARK: - Background Remover

/// Removes the background from a pet image using Vision's instance segmentation,
/// and composites the foreground onto a replacement background.
enum BackgroundRemover {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Public API

    /// Generates a foreground mask for the given image using `VNGenerateForegroundInstanceMaskRequest`.
    ///
    /// - Parameter image: The source CGImage.
    /// - Returns: A grayscale `CIImage` mask where white = foreground.
    /// - Throws: `BackgroundRemovalError` on failure.
    static func generateForegroundMask(from image: CGImage) async throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let result = request.results?.first else {
            throw BackgroundRemovalError.segmentationFailed
        }

        // Generate the mask pixel buffer from all detected instances.
        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw BackgroundRemovalError.maskGenerationFailed
        }

        return CIImage(cvPixelBuffer: maskBuffer)
    }

    /// Composites the foreground of an image onto a solid color or gradient background.
    ///
    /// - Parameters:
    ///   - image: The original image.
    ///   - mask: Foreground mask (white = keep).
    ///   - background: A `CIImage` to use as the background.
    /// - Returns: The composited `UIImage`.
    static func composite(
        image: CGImage,
        mask: CIImage,
        background: CIImage
    ) throws -> UIImage {
        let source = CIImage(cgImage: image)

        // Scale the mask to match the source.
        let maskScaleX = source.extent.width / mask.extent.width
        let maskScaleY = source.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: maskScaleX, y: maskScaleY))

        // Scale the background to match the source.
        let bgScaleX = source.extent.width / max(background.extent.width, 1)
        let bgScaleY = source.extent.height / max(background.extent.height, 1)
        let scaledBg = background.transformed(by: CGAffineTransform(scaleX: bgScaleX, y: bgScaleY))

        // Blend using the mask.
        let blended = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: scaledBg,
            kCIInputMaskImageKey: scaledMask,
        ])

        guard let outputCGImage = ciContext.createCGImage(blended, from: source.extent) else {
            throw BackgroundRemovalError.compositionFailed
        }

        return UIImage(cgImage: outputCGImage)
    }

    /// Composites the foreground onto a custom photo background.
    ///
    /// - Parameters:
    ///   - image: The original image.
    ///   - mask: Foreground mask.
    ///   - backgroundPhoto: A UIImage to use as the background.
    /// - Returns: The composited UIImage.
    static func composite(
        image: CGImage,
        mask: CIImage,
        backgroundPhoto: UIImage
    ) throws -> UIImage {
        guard let bgCG = backgroundPhoto.cgImage else {
            throw BackgroundRemovalError.imageConversionFailed
        }
        let bgCI = CIImage(cgImage: bgCG)
        return try composite(image: image, mask: mask, background: bgCI)
    }
}
