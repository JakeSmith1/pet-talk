import AVFoundation
import ImageIO
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

// MARK: - Error Types

enum GIFExportError: LocalizedError {
    case failedToCreateDestination
    case failedToCreateImageFromFrame
    case failedToFinalizeGIF
    case failedToReadVideo
    case noVideoTrack
    case invalidFrameCount

    var errorDescription: String? {
        switch self {
        case .failedToCreateDestination:
            return "Could not create the GIF output file."
        case .failedToCreateImageFromFrame:
            return "Failed to generate an image from a video frame."
        case .failedToFinalizeGIF:
            return "Could not finalize the GIF file."
        case .failedToReadVideo:
            return "Could not read the source video."
        case .noVideoTrack:
            return "The video file contains no video tracks."
        case .invalidFrameCount:
            return "No frames were provided for GIF creation."
        }
    }
}

// MARK: - GIF Configuration

struct GIFConfiguration {
    /// Frames per second for the output GIF. Lower values produce smaller files.
    var fps: Double = 10

    /// Maximum dimension (width or height) in pixels. The GIF is scaled proportionally.
    var maxDimension: CGFloat = 480

    /// Number of loop iterations. 0 means infinite looping.
    var loopCount: Int = 0

    /// Quality of color quantization. Range 0.0 (lowest)...1.0 (highest). Lower produces smaller files.
    var quality: Float = 0.8

    static let `default` = GIFConfiguration()

    static let compact = GIFConfiguration(fps: 8, maxDimension: 320, quality: 0.6)

    static let highQuality = GIFConfiguration(fps: 15, maxDimension: 640, quality: 1.0)
}

// MARK: - GIF Exporter

enum GIFExporter {

    /// Creates an animated GIF from an array of UIImage frames.
    ///
    /// - Parameters:
    ///   - frames: The source images in display order.
    ///   - configuration: GIF output settings.
    ///   - progressHandler: Called with progress values from 0.0 to 1.0.
    /// - Returns: File URL of the generated .gif file.
    static func exportGIF(
        from frames: [UIImage],
        configuration: GIFConfiguration = .default,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !frames.isEmpty else {
            throw GIFExportError.invalidFrameCount
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")

        let frameDelay = 1.0 / configuration.fps

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw GIFExportError.failedToCreateDestination
        }

        // GIF-level properties: loop count
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: configuration.loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Per-frame properties
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay
            ]
        ]

        for (index, frame) in frames.enumerated() {
            let resized = resizeImage(frame, maxDimension: configuration.maxDimension)

            guard let cgImage = resized.cgImage else {
                throw GIFExportError.failedToCreateImageFromFrame
            }

            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)

            let progress = Double(index + 1) / Double(frames.count)
            progressHandler(progress * 0.95) // Reserve 5% for finalization
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExportError.failedToFinalizeGIF
        }

        progressHandler(1.0)
        return outputURL
    }

    /// Creates an animated GIF by extracting frames from a video file at the configured fps.
    ///
    /// - Parameters:
    ///   - videoURL: URL of the source video.
    ///   - configuration: GIF output settings.
    ///   - progressHandler: Called with progress values from 0.0 to 1.0.
    /// - Returns: File URL of the generated .gif file.
    static func exportGIF(
        from videoURL: URL,
        configuration: GIFConfiguration = .default,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await CMTimeGetSeconds(asset.load(.duration))
        guard duration > 0 else {
            throw GIFExportError.failedToReadVideo
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.first != nil else {
            throw GIFExportError.noVideoTrack
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        // Scale down for the GIF
        generator.maximumSize = CGSize(
            width: configuration.maxDimension,
            height: configuration.maxDimension
        )

        let frameInterval = 1.0 / configuration.fps
        let totalFrames = Int(ceil(duration * configuration.fps))
        guard totalFrames > 0 else {
            throw GIFExportError.invalidFrameCount
        }

        // Generate requested times
        var times: [NSValue] = []
        for i in 0..<totalFrames {
            let time = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: 600)
            times.append(NSValue(time: time))
        }

        // Extract frames
        var frames: [UIImage] = []
        frames.reserveCapacity(totalFrames)

        // Use generateCGImagesAsynchronously for frame extraction
        let extractedFrames = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UIImage], Error>) in
            var collectedFrames: [UIImage] = []
            var collectedCount = 0

            generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, actualTime, result, error in
                collectedCount += 1

                if let cgImage = cgImage {
                    collectedFrames.append(UIImage(cgImage: cgImage))
                }

                let progress = Double(collectedCount) / Double(totalFrames) * 0.5
                Task { @MainActor in
                    progressHandler(progress)
                }

                if collectedCount == totalFrames {
                    continuation.resume(returning: collectedFrames)
                }
            }
        }

        guard !extractedFrames.isEmpty else {
            throw GIFExportError.invalidFrameCount
        }

        // Now create the GIF from extracted frames
        let gifURL = try await exportGIF(
            from: extractedFrames,
            configuration: configuration,
            progressHandler: { frameProgress in
                // Map frame progress (0...1) to overall progress (0.5...1.0)
                progressHandler(0.5 + frameProgress * 0.5)
            }
        )

        return gifURL
    }

    /// Creates an animated GIF from PetTalk project data (image + mouth animation + audio amplitudes).
    ///
    /// - Parameters:
    ///   - image: The pet photo.
    ///   - mouthRegion: The detected mouth region.
    ///   - amplitudes: Per-frame amplitude values.
    ///   - configuration: GIF output settings.
    ///   - progressHandler: Called with progress values from 0.0 to 1.0.
    /// - Returns: File URL of the generated .gif file.
    @MainActor
    static func exportGIF(
        image: UIImage,
        mouthRegion: MouthRegion,
        amplitudes: [Float],
        configuration: GIFConfiguration = .default,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !amplitudes.isEmpty else {
            throw GIFExportError.invalidFrameCount
        }

        // Sample amplitudes at the GIF frame rate (amplitudes are at 30fps)
        let sourceFPS: Double = 30
        let sampleStep = Int(max(1, sourceFPS / configuration.fps))
        let sampledAmplitudes = stride(from: 0, to: amplitudes.count, by: sampleStep).map { amplitudes[$0] }

        let renderSize = CGSize(
            width: configuration.maxDimension,
            height: configuration.maxDimension
        )

        var frames: [UIImage] = []
        frames.reserveCapacity(sampledAmplitudes.count)

        for (index, amplitude) in sampledAmplitudes.enumerated() {
            guard let pixelBuffer = MouthAnimatorRenderer.renderFrame(
                image: image,
                mouthRegion: mouthRegion,
                amplitude: amplitude,
                size: renderSize
            ) else {
                throw GIFExportError.failedToCreateImageFromFrame
            }

            if let uiImage = imageFromPixelBuffer(pixelBuffer) {
                frames.append(uiImage)
            }

            let progress = Double(index + 1) / Double(sampledAmplitudes.count) * 0.7
            progressHandler(progress)
        }

        let gifURL = try await exportGIF(
            from: frames,
            configuration: configuration,
            progressHandler: { frameProgress in
                progressHandler(0.7 + frameProgress * 0.3)
            }
        )

        return gifURL
    }

    // MARK: - Private Helpers

    /// Resizes an image so its largest dimension does not exceed `maxDimension`.
    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
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
