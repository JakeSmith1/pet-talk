import AVFoundation
import CoreGraphics
import UIKit

// MARK: - Error Types

enum DuetExportError: LocalizedError {
    case missingTrackData(String)
    case writerCreationFailed(Error)
    case writerStartFailed
    case renderFrameFailed(String, Int)
    case audioMixFailed
    case writingFailed(String)
    case finishWritingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTrackData(let track):
            return "Missing data for \(track). Please ensure both pets are configured."
        case .writerCreationFailed(let error):
            return "Failed to create video writer: \(error.localizedDescription)"
        case .writerStartFailed:
            return "Failed to start the asset writer."
        case .renderFrameFailed(let side, let frame):
            return "Failed to render \(side) frame \(frame)."
        case .audioMixFailed:
            return "Failed to mix audio from both tracks."
        case .writingFailed(let reason):
            return "Video writing failed: \(reason)"
        case .finishWritingFailed(let reason):
            return "Failed to finalize video: \(reason)"
        }
    }
}

// MARK: - Duet Video Exporter

enum DuetVideoExporter {

    /// Exports a side-by-side duet video compositing two animated pet tracks with their
    /// respective audio mixed together.
    ///
    /// - Parameters:
    ///   - leftTrack: The left pet's track data.
    ///   - rightTrack: The right pet's track data.
    ///   - layout: The side-by-side layout configuration.
    ///   - fps: Frames per second for the output video.
    ///   - progressHandler: Called on the main actor with values from 0.0 to 1.0.
    /// - Returns: The file URL of the exported .mp4 video.
    @MainActor
    static func export(
        leftTrack: PetTrack,
        rightTrack: PetTrack,
        layout: DuetLayout = .default,
        fps: Double = 30,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {

        // Validate inputs
        guard let leftImage = leftTrack.image,
              let leftMouth = leftTrack.mouthRegion,
              let leftAudioURL = leftTrack.effectiveAudioURL else {
            throw DuetExportError.missingTrackData("left pet")
        }

        guard let rightImage = rightTrack.image,
              let rightMouth = rightTrack.mouthRegion,
              let rightAudioURL = rightTrack.effectiveAudioURL else {
            throw DuetExportError.missingTrackData("right pet")
        }

        // Determine duration (use the longer audio track)
        let leftAsset = AVURLAsset(url: leftAudioURL)
        let rightAsset = AVURLAsset(url: rightAudioURL)

        let leftDuration = try await CMTimeGetSeconds(leftAsset.load(.duration))
        let rightDuration = try await CMTimeGetSeconds(rightAsset.load(.duration))
        let duration = max(leftDuration, rightDuration)

        guard duration > 0 else {
            throw DuetExportError.writingFailed("Audio duration is zero.")
        }

        let totalFrames = Int(ceil(duration * fps))
        let outputSize = layout.outputSize
        let panelSize = layout.panelSize

        // --- Prepare output file ---
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // --- Create AVAssetWriter ---
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw DuetExportError.writerCreationFailed(error)
        }

        // --- Video input (H.264) ---
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw DuetExportError.writerStartFailed
        }
        writer.add(videoInput)

        // --- Audio input (AAC, stereo for mixed output) ---
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(audioInput) else {
            throw DuetExportError.writerStartFailed
        }
        writer.add(audioInput)

        // --- Start writing ---
        guard writer.startWriting() else {
            throw DuetExportError.writerStartFailed
        }
        writer.startSession(atSourceTime: .zero)

        // Clean up the writer and temp file if export fails partway through.
        var writerFinished = false
        defer {
            if !writerFinished {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        // ============================================================
        // Phase 1: Write all video frames (side-by-side composition)
        // ============================================================
        let leftAmplitudes = leftTrack.amplitudes
        let rightAmplitudes = rightTrack.amplitudes

        // Create reusable render contexts — one per panel (SKView + scene + buffer pool).
        let leftContext = MouthAnimatorRenderer.RenderContext(image: leftImage, size: panelSize)
        let rightContext = MouthAnimatorRenderer.RenderContext(image: rightImage, size: panelSize)

        for frame in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            // Get amplitudes for this frame
            let leftAmplitude: Float
            if leftAmplitudes.isEmpty {
                leftAmplitude = 0
            } else {
                leftAmplitude = leftAmplitudes[min(frame, leftAmplitudes.count - 1)]
            }

            let rightAmplitude: Float
            if rightAmplitudes.isEmpty {
                rightAmplitude = 0
            } else {
                rightAmplitude = rightAmplitudes[min(frame, rightAmplitudes.count - 1)]
            }

            // Render both panels using reusable contexts.
            guard let leftBuffer = leftContext.renderFrame(
                amplitude: leftAmplitude,
                mouthRegion: leftMouth
            ) else {
                throw DuetExportError.renderFrameFailed("left", frame)
            }

            guard let rightBuffer = rightContext.renderFrame(
                amplitude: rightAmplitude,
                mouthRegion: rightMouth
            ) else {
                throw DuetExportError.renderFrameFailed("right", frame)
            }

            // Composite side-by-side into a single frame
            guard let composited = compositeSideBySide(
                left: leftBuffer,
                right: rightBuffer,
                outputSize: outputSize,
                dividerWidth: layout.dividerWidth,
                backgroundColor: layout.backgroundColor
            ) else {
                throw DuetExportError.renderFrameFailed("composite", frame)
            }

            let presentationTime = CMTimeMake(value: Int64(frame), timescale: Int32(fps))
            guard adaptor.append(composited, withPresentationTime: presentationTime) else {
                throw DuetExportError.writingFailed("Failed to append frame \(frame)")
            }

            let videoProgress = Double(frame + 1) / Double(totalFrames) * 0.7
            progressHandler(videoProgress)
        }

        videoInput.markAsFinished()

        // ============================================================
        // Phase 2: Write mixed audio
        // ============================================================
        try await writeMixedAudio(
            leftAudioURL: leftAudioURL,
            rightAudioURL: rightAudioURL,
            audioInput: audioInput,
            duration: duration,
            progressHandler: { audioProgress in
                // Map audio progress (0...1) to overall progress (0.7...0.9).
                progressHandler(0.7 + audioProgress * 0.2)
            }
        )

        audioInput.markAsFinished()

        // ============================================================
        // Phase 3: Finalize
        // ============================================================
        progressHandler(0.9)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            let message = writer.error?.localizedDescription ?? "Unknown error"
            throw DuetExportError.finishWritingFailed(message)
        }

        writerFinished = true
        progressHandler(0.95)
        progressHandler(1.0)
        return outputURL
    }

    // MARK: - Side-by-Side Composition

    /// Composites two pixel buffers side by side into a single output buffer.
    private static func compositeSideBySide(
        left: CVPixelBuffer,
        right: CVPixelBuffer,
        outputSize: CGSize,
        dividerWidth: CGFloat,
        backgroundColor: CGColor
    ) -> CVPixelBuffer? {
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
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

        // Fill background
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let panelWidth = (CGFloat(width) - dividerWidth) / 2

        // Draw left panel
        if let leftImage = cgImageFromPixelBuffer(left) {
            let leftRect = CGRect(x: 0, y: 0, width: panelWidth, height: CGFloat(height))
            context.draw(leftImage, in: leftRect)
        }

        // Draw right panel
        if let rightImage = cgImageFromPixelBuffer(right) {
            let rightRect = CGRect(
                x: panelWidth + dividerWidth,
                y: 0,
                width: panelWidth,
                height: CGFloat(height)
            )
            context.draw(rightImage, in: rightRect)
        }

        return buffer
    }

    // MARK: - Audio Mixing

    /// Writes interleaved audio from both tracks to the writer input.
    /// Uses AVComposition to mix the two audio files together.
    nonisolated private static func writeMixedAudio(
        leftAudioURL: URL,
        rightAudioURL: URL,
        audioInput: AVAssetWriterInput,
        duration: Double,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws {
        // Create a composition with both audio tracks
        let composition = AVMutableComposition()
        let leftAsset = AVURLAsset(url: leftAudioURL)
        let rightAsset = AVURLAsset(url: rightAudioURL)

        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 44100)
        )

        // Add left audio track
        if let leftAudioTrack = try await leftAsset.loadTracks(withMediaType: .audio).first,
           let compositionLeftTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let leftDuration = try await leftAsset.load(.duration)
            let leftRange = CMTimeRange(
                start: .zero,
                duration: min(leftDuration, timeRange.duration)
            )
            try compositionLeftTrack.insertTimeRange(leftRange, of: leftAudioTrack, at: .zero)
        }

        // Add right audio track
        if let rightAudioTrack = try await rightAsset.loadTracks(withMediaType: .audio).first,
           let compositionRightTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let rightDuration = try await rightAsset.load(.duration)
            let rightRange = CMTimeRange(
                start: .zero,
                duration: min(rightDuration, timeRange.duration)
            )
            try compositionRightTrack.insertTimeRange(rightRange, of: rightAudioTrack, at: .zero)
        }

        // Read mixed audio from composition
        let reader = try AVAssetReader(asset: composition)
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let audioMix = AVMutableAudioMix()
        var inputParameters: [AVMutableAudioMixInputParameters] = []

        let compositionTracks = try await composition.loadTracks(withMediaType: .audio)
        for track in compositionTracks {
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(0.8, at: .zero) // Slightly reduce each to prevent clipping
            inputParameters.append(params)
        }
        audioMix.inputParameters = inputParameters

        let readerOutput = AVAssetReaderAudioMixOutput(
            audioTracks: compositionTracks,
            audioSettings: readerOutputSettings
        )
        readerOutput.audioMix = audioMix

        guard reader.canAdd(readerOutput) else {
            throw DuetExportError.audioMixFailed
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw DuetExportError.audioMixFailed
        }

        while reader.status == .reading {
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                if !audioInput.append(sampleBuffer) {
                    break
                }
                // Report audio progress based on presentation timestamp.
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if pts.isValid, duration > 0 {
                    let currentSeconds = CMTimeGetSeconds(pts)
                    let audioProgress = min(max(currentSeconds / duration, 0.0), 1.0)
                    progressHandler(audioProgress)
                }
            } else {
                break
            }
        }
        progressHandler(1.0)
    }

    // MARK: - Helpers

    private static func cgImageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
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
              ) else {
            return nil
        }

        return context.makeImage()
    }
}
