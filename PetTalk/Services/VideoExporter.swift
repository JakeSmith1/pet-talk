import AVFoundation
import CoreImage
import UIKit

// MARK: - Error Types

enum VideoExportError: LocalizedError {
    case missingImage
    case missingMouthRegion
    case missingAudioTrack
    case writerCreationFailed(Error)
    case writerStartFailed
    case renderFrameFailed(Int)
    case audioReaderStartFailed
    case writingFailed(String)
    case writeFailed(String)
    case finishWritingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "No image provided for video export."
        case .missingMouthRegion:
            return "No mouth region defined for animation."
        case .missingAudioTrack:
            return "The audio file contains no audio tracks."
        case .writerCreationFailed(let error):
            return "Failed to create video writer: \(error.localizedDescription)"
        case .writerStartFailed:
            return "Failed to start the asset writer."
        case .renderFrameFailed(let frame):
            return "Failed to render video frame \(frame)."
        case .audioReaderStartFailed:
            return "Failed to start reading audio samples."
        case .writeFailed(let reason):
            return "Failed to write frame: \(reason)"
        case .writingFailed(let reason):
            return "Video writing failed: \(reason)"
        case .finishWritingFailed(let reason):
            return "Failed to finalize video: \(reason)"
        }
    }
}

// MARK: - Video Exporter

enum VideoExporter {

    /// Configuration for visual effects applied during export.
    struct VisualEffectsConfig {
        var filter: CartoonFilterPreset = .none
        var enableEyeAnimation: Bool = false
        var eyeRegion: EyeRegion?
        var eyeKeyframes: [EyeKeyframe] = []
        var selectedBackground: BackgroundScene?
        var customBackgroundImage: UIImage?
        var foregroundMask: CIImage?
        var accessories: [AccessoryPlacement] = []
    }

    /// Exports an animated "talking pet" video by compositing mouth animation frames
    /// with the provided audio track, applying visual effects.
    ///
    /// - Parameters:
    ///   - image: The source pet image.
    ///   - mouthRegion: The detected mouth region to animate.
    ///   - audioURL: URL of the recorded audio file.
    ///   - amplitudes: Per-frame amplitude values driving mouth openness.
    ///   - fps: Frames per second for the output video.
    ///   - size: Output video dimensions.
    ///   - effects: Visual effects configuration (filter, background, accessories, eye animation).
    ///   - progressHandler: Called on the main actor with values from 0.0 to 1.0.
    /// - Returns: The file URL of the exported .mp4 video.
    static func export(
        image: UIImage,
        mouthRegion: MouthRegion,
        audioURL: URL,
        amplitudes: [Float],
        fps: Double = 30,
        size: CGSize = CGSize(width: 1080, height: 1080),
        effects: VisualEffectsConfig = VisualEffectsConfig(),
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {

        // --- Determine audio duration ---
        let audioAsset = AVURLAsset(url: audioURL)
        let duration: CMTime = try await audioAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else {
            throw VideoExportError.writingFailed("Audio duration is zero.")
        }

        let totalFrames = Int(ceil(durationSeconds * fps))

        // --- Prepare output file ---
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // --- Create AVAssetWriter ---
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw VideoExportError.writerCreationFailed(error)
        }

        // --- Video input (H.264) ---
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw VideoExportError.writerStartFailed
        }
        writer.add(videoInput)

        // --- Audio input (AAC) — read source format for sample rate and channels ---
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            throw VideoExportError.missingAudioTrack
        }
        let sourceDescriptions = try await sourceAudioTrack.load(.formatDescriptions)
        let sourceASBD = sourceDescriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let exportSampleRate = sourceASBD?.mSampleRate ?? 44100
        let exportChannels = sourceASBD.map { max(Int($0.mChannelsPerFrame), 1) } ?? 2

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: exportSampleRate,
            AVNumberOfChannelsKey: exportChannels,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(audioInput) else {
            throw VideoExportError.writerStartFailed
        }
        writer.add(audioInput)

        // --- Start writing ---
        guard writer.startWriting() else {
            throw VideoExportError.writerStartFailed
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
        // Phase 1: Write all video frames
        // ============================================================

        // Create a reusable render context once (SKView + scene + pixel buffer pool).
        let renderContext = await MainActor.run {
            MouthAnimatorRenderer.RenderContext(image: image, size: size)
        }

        for frame in 0..<totalFrames {
            // Wait until the input is ready to accept more data.
            var readyWaitCount = 0
            while !videoInput.isReadyForMoreMediaData {
                readyWaitCount += 1
                if readyWaitCount > 500 { // ~5 seconds
                    throw VideoExportError.writingFailed("Writer input not ready after timeout")
                }
                if writer.status == .failed {
                    throw VideoExportError.writingFailed(writer.error?.localizedDescription ?? "Writer failed")
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
            }

            // Look up the amplitude for this frame.
            let amplitude: Float
            if amplitudes.isEmpty {
                amplitude = 0
            } else {
                let index = min(frame, amplitudes.count - 1)
                amplitude = amplitudes[index]
            }

            // Render using the reusable context (only updates warp + snapshots).
            let maybeBuffer: CVPixelBuffer? = await MainActor.run {
                renderContext.renderFrame(amplitude: amplitude, mouthRegion: mouthRegion)
            }
            guard var pixelBuffer = maybeBuffer else {
                throw VideoExportError.renderFrameFailed(frame)
            }

            // Apply cartoon filter if selected.
            if effects.filter != .none {
                pixelBuffer = CartoonFilter.apply(to: pixelBuffer, preset: effects.filter)
            }

            let presentationTime = CMTimeMake(value: Int64(frame), timescale: Int32(fps))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw VideoExportError.writeFailed("Failed to append video frame \(frame)")
            }

            // Report progress every 10 frames (video phase is 0.0 – 0.8).
            if frame % 10 == 0 || frame == totalFrames - 1 {
                let videoProgress = Double(frame + 1) / Double(totalFrames) * 0.8
                progressHandler(videoProgress)
            }
        }

        videoInput.markAsFinished()

        // ============================================================
        // Phase 2: Write audio samples
        // ============================================================
        let audioTrack = sourceAudioTrack

        let reader = try AVAssetReader(asset: audioAsset)
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: readerOutputSettings
        )

        guard reader.canAdd(readerOutput) else {
            throw VideoExportError.audioReaderStartFailed
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw VideoExportError.audioReaderStartFailed
        }

        while reader.status == .reading {
            // Wait for writer input readiness.
            var audioReadyWaitCount = 0
            while !audioInput.isReadyForMoreMediaData {
                audioReadyWaitCount += 1
                if audioReadyWaitCount > 500 { // ~5 seconds
                    throw VideoExportError.writingFailed("Audio input not ready after timeout")
                }
                if writer.status == .failed {
                    throw VideoExportError.writingFailed(writer.error?.localizedDescription ?? "Writer failed")
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
            }

            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                if !audioInput.append(sampleBuffer) {
                    break
                }
                // Report audio progress based on presentation timestamp.
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if pts.isValid, durationSeconds > 0 {
                    let audioProgress = min(CMTimeGetSeconds(pts) / durationSeconds, 1.0)
                    // Map audio progress (0...1) to overall progress (0.8...0.9).
                    progressHandler(0.8 + audioProgress * 0.1)
                }
            } else {
                // No more samples to read.
                break
            }
        }

        audioInput.markAsFinished()

        progressHandler(0.9)

        // ============================================================
        // Phase 3: Finalize
        // ============================================================
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            let message = writer.error?.localizedDescription ?? "Unknown error"
            throw VideoExportError.finishWritingFailed(message)
        }

        writerFinished = true
        progressHandler(0.95)
        progressHandler(1.0)

        return outputURL
    }
}
