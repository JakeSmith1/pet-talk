import CoreImage
import SwiftUI

// MARK: - Background Scene Model

/// A gradient-based background scene that can replace the original image background.
struct BackgroundScene: Identifiable, Hashable {
    let id: String
    let name: String
    let category: Category
    /// Gradient colors (top to bottom).
    let colors: [Color]

    enum Category: String, CaseIterable, Identifiable {
        case nature = "Nature"
        case abstract = "Abstract"
        case solid = "Solid"

        var id: String { rawValue }
    }

    /// Returns a `CIImage` gradient suitable for compositing at the given size.
    func ciImage(size: CGSize) -> CIImage {
        let width = Int(size.width)
        let height = Int(size.height)

        // Resolve SwiftUI Colors to CGColors for Core Image.
        let cgColors: [CGColor] = colors.map { color in
            UIColor(color).cgColor
        }

        guard cgColors.count >= 2,
              let startColor = cgColors.first,
              let endColor = cgColors.last else {
            // Fallback: solid black.
            return CIImage(color: CIColor.black)
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let startCI = CIColor(cgColor: startColor)
        let endCI = CIColor(cgColor: endColor)

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height)) // top
        gradient.point1 = CGPoint(x: CGFloat(width) / 2, y: 0)               // bottom
        gradient.color0 = startCI
        gradient.color1 = endCI

        return (gradient.outputImage ?? CIImage())
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }
}

// MARK: - Background Scene Catalog

extension BackgroundScene {

    static let catalog: [BackgroundScene] = [
        // Nature
        BackgroundScene(id: "bg_sunset", name: "Sunset", category: .nature,
                        colors: [Color.orange, Color.pink]),
        BackgroundScene(id: "bg_ocean", name: "Ocean", category: .nature,
                        colors: [Color.cyan, Color.blue]),
        BackgroundScene(id: "bg_forest", name: "Forest", category: .nature,
                        colors: [Color.green, Color(red: 0.1, green: 0.3, blue: 0.1)]),
        BackgroundScene(id: "bg_sky", name: "Sky", category: .nature,
                        colors: [Color(red: 0.5, green: 0.8, blue: 1.0), Color.blue]),

        // Abstract
        BackgroundScene(id: "bg_neon", name: "Neon", category: .abstract,
                        colors: [Color.purple, Color(red: 1.0, green: 0.0, blue: 0.5)]),
        BackgroundScene(id: "bg_galaxy", name: "Galaxy", category: .abstract,
                        colors: [Color(red: 0.1, green: 0.0, blue: 0.2), Color.indigo]),
        BackgroundScene(id: "bg_lava", name: "Lava", category: .abstract,
                        colors: [Color.red, Color(red: 0.3, green: 0.0, blue: 0.0)]),

        // Solid
        BackgroundScene(id: "bg_white", name: "White", category: .solid,
                        colors: [Color.white, Color.white]),
        BackgroundScene(id: "bg_black", name: "Black", category: .solid,
                        colors: [Color.black, Color.black]),
        BackgroundScene(id: "bg_green_screen", name: "Green Screen", category: .solid,
                        colors: [Color.green, Color.green]),
    ]

    static func scenes(in category: Category) -> [BackgroundScene] {
        catalog.filter { $0.category == category }
    }
}
