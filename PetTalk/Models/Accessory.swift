import CoreGraphics
import Foundation

// MARK: - Accessory Model

/// A decorative accessory that can be overlaid on the pet image.
struct Accessory: Identifiable, Hashable {
    let id: String
    let name: String
    let category: Category
    /// SF Symbol name used for rendering.
    let sfSymbol: String
    /// Default anchor relative to the pet's face (in normalized 0...1 coordinates).
    let defaultAnchor: AnchorPreset

    enum Category: String, CaseIterable, Identifiable {
        case hats = "Hats"
        case glasses = "Glasses"
        case bowTies = "Bow Ties"
        case misc = "Misc"

        var id: String { rawValue }

        var sfSymbolHeader: String {
            switch self {
            case .hats: return "crown"
            case .glasses: return "eyeglasses"
            case .bowTies: return "bowtie"
            case .misc: return "sparkles"
            }
        }
    }

    /// Predefined anchor positions relative to the face bounding box.
    enum AnchorPreset: String, Hashable {
        case topHead      // above forehead
        case eyes         // over eye region
        case nose         // on nose
        case belowMouth   // below mouth/chin area
        case center       // center of face
    }
}

// MARK: - Accessory Placement

/// Tracks the user-customized placement of an accessory in the scene.
struct AccessoryPlacement: Identifiable, Equatable {
    var id: String { accessory.id }
    let accessory: Accessory
    /// Offset from the default anchor in points (user drag).
    var offset: CGSize = .zero
    /// Scale factor (user pinch). 1.0 = default size.
    var scale: CGFloat = 1.0
}

// MARK: - Accessory Catalog

extension Accessory {

    /// The full catalog of built-in accessories.
    static let catalog: [Accessory] = [
        // Hats
        Accessory(id: "hat_crown", name: "Crown", category: .hats, sfSymbol: "crown.fill", defaultAnchor: .topHead),
        Accessory(id: "hat_party", name: "Party Hat", category: .hats, sfSymbol: "party.popper.fill", defaultAnchor: .topHead),
        Accessory(id: "hat_grad", name: "Grad Cap", category: .hats, sfSymbol: "graduationcap.fill", defaultAnchor: .topHead),

        // Glasses
        Accessory(id: "glasses_sun", name: "Sunglasses", category: .glasses, sfSymbol: "sunglasses.fill", defaultAnchor: .eyes),
        Accessory(id: "glasses_regular", name: "Eyeglasses", category: .glasses, sfSymbol: "eyeglasses", defaultAnchor: .eyes),
        Accessory(id: "glasses_monocle", name: "Monocle", category: .glasses, sfSymbol: "circle", defaultAnchor: .eyes),

        // Bow Ties
        Accessory(id: "bowtie_classic", name: "Bow Tie", category: .bowTies, sfSymbol: "bowtie.fill", defaultAnchor: .belowMouth),
        Accessory(id: "bowtie_necktie", name: "Necktie", category: .bowTies, sfSymbol: "tshirt.fill", defaultAnchor: .belowMouth),
        Accessory(id: "bowtie_bandana", name: "Bandana", category: .bowTies, sfSymbol: "triangle.fill", defaultAnchor: .belowMouth),

        // Misc
        Accessory(id: "misc_star", name: "Star", category: .misc, sfSymbol: "star.fill", defaultAnchor: .center),
        Accessory(id: "misc_heart", name: "Heart", category: .misc, sfSymbol: "heart.fill", defaultAnchor: .center),
        Accessory(id: "misc_sparkle", name: "Sparkle", category: .misc, sfSymbol: "sparkle", defaultAnchor: .nose),
    ]

    /// Returns all accessories in a given category.
    static func accessories(in category: Category) -> [Accessory] {
        catalog.filter { $0.category == category }
    }
}
