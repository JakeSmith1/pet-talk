import PhotosUI
import SwiftUI

// MARK: - Background Picker View

/// Grid of gradient swatches with category tabs, a "None" option, and photo import.
struct BackgroundPickerView: View {
    @Binding var selectedBackground: BackgroundScene?
    @Binding var customBackgroundImage: UIImage?

    @State private var activeCategory: BackgroundScene.Category = .nature
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 12) {
            // Category tabs + special options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "None" button
                    noneButton

                    // Photo import
                    photoImportButton

                    Divider()
                        .frame(height: 24)

                    ForEach(BackgroundScene.Category.allCases) { category in
                        categoryButton(category)
                    }
                }
                .padding(.horizontal, 4)
            }

            // Scene grid (hidden when "None" is active and no custom image)
            if selectedBackground != nil || customBackgroundImage != nil {
                sceneGrid
            }
        }
    }

    // MARK: - Subviews

    private var noneButton: some View {
        Button {
            selectedBackground = nil
            customBackgroundImage = nil
        } label: {
            Text("None")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedBackground == nil && customBackgroundImage == nil
                              ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundStyle(selectedBackground == nil && customBackgroundImage == nil ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var photoImportButton: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Label("Photo", systemImage: "photo.on.rectangle")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(customBackgroundImage != nil ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundStyle(customBackgroundImage != nil ? .white : .primary)
        }
        .onChange(of: photoPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    customBackgroundImage = uiImage
                    selectedBackground = nil
                }
            }
        }
    }

    private func categoryButton(_ category: BackgroundScene.Category) -> some View {
        Button {
            activeCategory = category
            customBackgroundImage = nil
        } label: {
            Text(category.rawValue)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(activeCategory == category && customBackgroundImage == nil && selectedBackground != nil
                              ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundStyle(
                    activeCategory == category && customBackgroundImage == nil && selectedBackground != nil
                    ? .white : .primary
                )
        }
        .buttonStyle(.plain)
    }

    private var sceneGrid: some View {
        let scenes = BackgroundScene.scenes(in: activeCategory)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
            ForEach(scenes) { scene in
                Button {
                    selectedBackground = scene
                    customBackgroundImage = nil
                } label: {
                    GradientSwatchView(scene: scene, isSelected: selectedBackground?.id == scene.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Gradient Swatch

private struct GradientSwatchView: View {
    let scene: BackgroundScene
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            LinearGradient(
                colors: scene.colors,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(scene.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("\(scene.name) background\(isSelected ? ", selected" : "")")
    }
}
