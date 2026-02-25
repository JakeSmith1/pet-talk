import CoreGraphics
import UIKit
import Vision

// MARK: - Error Types

enum StickerExportError: LocalizedError {
    case noAmplitudes
    case noFramesExtracted
    case faceCropFailed
    case exportFailed(String)
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .noAmplitudes:
            return "No amplitude data available for sticker extraction."
        case .noFramesExtracted:
            return "Could not extract any key frames for stickers."
        case .faceCropFailed:
            return "Failed to crop the face region from the image."
        case .exportFailed(let reason):
            return "Sticker export failed: \(reason)"
        case .directoryCreationFailed:
            return "Could not create the sticker output directory."
        }
    }
}

// MARK: - Sticker Pack Exporter

enum StickerPackExporter {

    /// The default number of stickers to extract from an animation.
    static let defaultStickerCount = 6

    /// Extracts a sticker pack from PetTalk project data by selecting key frames with
    /// varied mouth positions and cropping to the pet's face region.
    ///
    /// - Parameters:
    ///   - image: The source pet photo.
    ///   - mouthRegion: The detected mouth region.
    ///   - amplitudes: Per-frame amplitude values at 30fps.
    ///   - style: Sticker crop and style configuration.
    ///   - stickerCount: Number of stickers to generate.
    ///   - progressHandler: Called with progress from 0.0 to 1.0.
    /// - Returns: A `StickerPack` containing the extracted stickers.
    @MainActor
    static func extractStickerPack(
        image: UIImage,
        mouthRegion: MouthRegion,
        amplitudes: [Float],
        style: StickerStyle = .default,
        stickerCount: Int = defaultStickerCount,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> StickerPack {
        guard !amplitudes.isEmpty else {
            throw StickerExportError.noAmplitudes
        }

        // Step 1: Select key frame indices with diverse amplitudes
        let keyFrameIndices = selectKeyFrameIndices(
            amplitudes: amplitudes,
            count: stickerCount
        )

        guard !keyFrameIndices.isEmpty else {
            throw StickerExportError.noFramesExtracted
        }

        progressHandler(0.1)

        // Step 2: Determine the face crop region from the mouth region
        let faceBounds = computeFaceBounds(
            mouthRegion: mouthRegion,
            imageSize: image.size,
            padding: style.padding
        )

        progressHandler(0.2)

        // Step 3: Render each key frame and crop to face
        var stickers: [StickerItem] = []
        let renderSize = style.outputSize

        for (index, frameIndex) in keyFrameIndices.enumerated() {
            let amplitude = amplitudes[frameIndex]

            // Render the animated frame
            guard let pixelBuffer = MouthAnimatorRenderer.renderFrame(
                image: image,
                mouthRegion: mouthRegion,
                amplitude: amplitude,
                size: CGSize(width: image.size.width, height: image.size.height)
            ) else {
                continue
            }

            // Convert pixel buffer to UIImage
            guard let fullImage = imageFromPixelBuffer(pixelBuffer) else {
                continue
            }

            // Crop to face region
            guard let croppedImage = cropImage(
                fullImage,
                to: faceBounds,
                outputSize: renderSize,
                circularCrop: style.circularCrop,
                addBorder: style.addBorder,
                borderWidth: style.borderWidth
            ) else {
                continue
            }

            let label = stickerLabel(for: amplitude, index: index)
            let timestamp = TimeInterval(frameIndex) / 30.0

            let sticker = StickerItem(
                image: croppedImage,
                sourceFrameIndex: frameIndex,
                amplitude: amplitude,
                label: label,
                timestamp: timestamp
            )
            stickers.append(sticker)

            let progress = 0.2 + Double(index + 1) / Double(keyFrameIndices.count) * 0.7
            progressHandler(progress)
        }

        guard !stickers.isEmpty else {
            throw StickerExportError.noFramesExtracted
        }

        progressHandler(0.95)

        let pack = StickerPack(stickers: stickers)

        progressHandler(1.0)

        return pack
    }

    /// Exports a sticker pack to individual PNG files in a temporary directory.
    ///
    /// - Parameters:
    ///   - pack: The sticker pack to export.
    ///   - progressHandler: Called with progress from 0.0 to 1.0.
    /// - Returns: Array of file URLs for the exported PNG files.
    static func exportAsPNGs(
        pack: StickerPack,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) throws -> [URL] {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stickers_\(pack.id.uuidString)")

        // Create the directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw StickerExportError.directoryCreationFailed
            }
        }

        var urls: [URL] = []

        for (index, sticker) in pack.stickers.enumerated() {
            let fileName = "sticker_\(String(format: "%02d", index + 1))_\(sticker.label.lowercased().replacingOccurrences(of: " ", with: "_")).png"
            let fileURL = directoryURL.appendingPathComponent(fileName)

            guard let pngData = sticker.image.pngData() else {
                throw StickerExportError.exportFailed("Failed to generate PNG data for sticker \(index + 1).")
            }

            try pngData.write(to: fileURL)
            urls.append(fileURL)

            let progress = Double(index + 1) / Double(pack.stickers.count)
            progressHandler(progress)
        }

        return urls
    }

    // MARK: - Key Frame Selection

    /// Selects frame indices that represent a diverse range of mouth positions.
    /// Always includes the frame with minimum amplitude (closed mouth) and maximum
    /// amplitude (widest open), then fills remaining slots evenly across amplitude range.
    private static func selectKeyFrameIndices(
        amplitudes: [Float],
        count: Int
    ) -> [Int] {
        guard !amplitudes.isEmpty else { return [] }

        let clampedCount = min(count, amplitudes.count)
        guard clampedCount > 0 else { return [] }

        if clampedCount == 1 {
            // Just pick the frame with maximum amplitude
            let maxIndex = amplitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            return [maxIndex]
        }

        // Find min and max amplitude frames
        var minIndex = 0
        var maxIndex = 0
        for i in amplitudes.indices {
            if amplitudes[i] < amplitudes[minIndex] { minIndex = i }
            if amplitudes[i] > amplitudes[maxIndex] { maxIndex = i }
        }

        var selectedIndices: Set<Int> = [minIndex, maxIndex]

        // For remaining slots, divide the amplitude range into buckets and pick the
        // best representative frame from each bucket.
        let remainingCount = clampedCount - selectedIndices.count
        if remainingCount > 0 {
            let minAmplitude = amplitudes[minIndex]
            let maxAmplitude = amplitudes[maxIndex]
            let range = maxAmplitude - minAmplitude

            if range > .ulpOfOne {
                let bucketCount = remainingCount + 1
                for bucket in 1...remainingCount {
                    let targetAmplitude = minAmplitude + range * Float(bucket) / Float(bucketCount)

                    // Find the frame closest to this target amplitude that is not already selected
                    // and is sufficiently spaced from already selected frames.
                    var bestIndex: Int?
                    var bestDistance: Float = .greatestFiniteMagnitude

                    for (i, amp) in amplitudes.enumerated() {
                        guard !selectedIndices.contains(i) else { continue }
                        let distance = abs(amp - targetAmplitude)
                        if distance < bestDistance {
                            bestDistance = distance
                            bestIndex = i
                        }
                    }

                    if let index = bestIndex {
                        selectedIndices.insert(index)
                    }
                }
            } else {
                // All amplitudes are the same; just pick evenly spaced frames
                let step = max(1, amplitudes.count / (clampedCount + 1))
                for i in 1...remainingCount {
                    let index = min(i * step, amplitudes.count - 1)
                    selectedIndices.insert(index)
                }
            }
        }

        // Return sorted by frame index (chronological order)
        return Array(selectedIndices).sorted()
    }

    // MARK: - Face Bounds Computation

    /// Computes a square face crop region centered above the mouth.
    private static func computeFaceBounds(
        mouthRegion: MouthRegion,
        imageSize: CGSize,
        padding: CGFloat
    ) -> CGRect {
        // The mouth region uses Vision normalized coordinates (origin bottom-left).
        // Convert to UIKit coordinates (origin top-left) for cropping.
        let mouthCenterX = mouthRegion.center.x * imageSize.width
        let mouthCenterY = (1.0 - mouthRegion.center.y) * imageSize.height

        // Estimate face size as proportional to mouth radius
        let mouthRadiusPixels = mouthRegion.radius * min(imageSize.width, imageSize.height)
        let estimatedFaceSize = mouthRadiusPixels * 6.0

        // Center the crop slightly above the mouth (the face center is above the mouth)
        let faceCenterX = mouthCenterX
        let faceCenterY = mouthCenterY - estimatedFaceSize * 0.15

        // Apply padding
        let paddedSize = estimatedFaceSize * (1.0 + padding)

        // Compute the crop rectangle
        var cropRect = CGRect(
            x: faceCenterX - paddedSize / 2,
            y: faceCenterY - paddedSize / 2,
            width: paddedSize,
            height: paddedSize
        )

        // Clamp to image bounds
        cropRect.origin.x = max(0, cropRect.origin.x)
        cropRect.origin.y = max(0, cropRect.origin.y)
        cropRect.size.width = min(cropRect.size.width, imageSize.width - cropRect.origin.x)
        cropRect.size.height = min(cropRect.size.height, imageSize.height - cropRect.origin.y)

        return cropRect
    }

    // MARK: - Image Cropping

    /// Crops a UIImage to the specified rectangle and optionally applies styling.
    private static func cropImage(
        _ image: UIImage,
        to rect: CGRect,
        outputSize: CGSize,
        circularCrop: Bool,
        addBorder: Bool,
        borderWidth: CGFloat
    ) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: outputSize)

        return renderer.image { context in
            let drawRect = CGRect(origin: .zero, size: outputSize)

            // Apply circular clipping if requested
            if circularCrop {
                let circlePath = UIBezierPath(ovalIn: drawRect.insetBy(
                    dx: addBorder ? borderWidth : 0,
                    dy: addBorder ? borderWidth : 0
                ))
                circlePath.addClip()
            }

            // Draw the cropped portion of the source image scaled to fill the output
            // Draw the source rect into the output rect
            if let cg = image.cgImage, let cropped = cg.cropping(to: rect) {
                UIImage(cgImage: cropped).draw(in: drawRect)
            }

            // Draw border if requested
            if addBorder {
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(borderWidth)

                if circularCrop {
                    let borderRect = drawRect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
                    context.cgContext.strokeEllipse(in: borderRect)
                } else {
                    let borderRect = drawRect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
                    context.cgContext.stroke(borderRect)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func stickerLabel(for amplitude: Float, index: Int) -> String {
        switch amplitude {
        case 0..<0.1:
            return "Silent"
        case 0.1..<0.3:
            return "Whisper"
        case 0.3..<0.6:
            return "Talking \(index + 1)"
        case 0.6..<0.85:
            return "Loud \(index + 1)"
        default:
            return "Yelling"
        }
    }

    /// Converts a CVPixelBuffer to a UIImage.
    private static func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                            CGImageAlphaInfo.premultipliedFirst.rawValue
              ),
              let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
