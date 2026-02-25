import Foundation
import UIKit

// MARK: - Sticker Item

/// Represents a single sticker extracted from a PetTalk animation.
struct StickerItem: Identifiable, Equatable {
    /// Unique identifier for this sticker.
    let id: UUID

    /// The cropped face image for this sticker.
    let image: UIImage

    /// The frame index from the source animation this sticker was extracted from.
    let sourceFrameIndex: Int

    /// The mouth amplitude at the time of extraction (0...1).
    let amplitude: Float

    /// Display label for the sticker (e.g., "Talking 1", "Closed Mouth").
    let label: String

    /// The timestamp in the source animation, if applicable.
    let timestamp: TimeInterval?

    init(
        id: UUID = UUID(),
        image: UIImage,
        sourceFrameIndex: Int,
        amplitude: Float,
        label: String,
        timestamp: TimeInterval? = nil
    ) {
        self.id = id
        self.image = image
        self.sourceFrameIndex = sourceFrameIndex
        self.amplitude = amplitude
        self.label = label
        self.timestamp = timestamp
    }

    static func == (lhs: StickerItem, rhs: StickerItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sticker Pack

/// A collection of stickers derived from a single PetTalk project.
struct StickerPack: Identifiable {
    let id: UUID
    let name: String
    let stickers: [StickerItem]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Pet Stickers",
        stickers: [StickerItem],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.stickers = stickers
        self.createdAt = createdAt
    }
}

// MARK: - Sticker Style

/// Configuration for how stickers are cropped and styled.
struct StickerStyle: Equatable {
    /// Padding around the detected face, as a fraction of the crop region (0.0...1.0).
    var padding: CGFloat = 0.25

    /// Whether to apply a circular crop mask.
    var circularCrop: Bool = false

    /// Whether to add a white border/outline.
    var addBorder: Bool = true

    /// Border width in points (only used when `addBorder` is true).
    var borderWidth: CGFloat = 4

    /// Output size in pixels for each sticker.
    var outputSize: CGSize = CGSize(width: 512, height: 512)

    /// Whether to remove the background (attempt transparency).
    var transparentBackground: Bool = true

    static let `default` = StickerStyle()
}
