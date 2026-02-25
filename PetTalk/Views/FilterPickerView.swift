import SwiftUI

// MARK: - Filter Picker View

/// A horizontal scrolling strip showing live-thumbnail previews of each cartoon filter.
struct FilterPickerView: View {
    @Binding var selectedFilter: CartoonFilterPreset
    let sourceImage: UIImage?

    /// Cached thumbnails keyed by preset ID.
    @State private var thumbnails: [String: UIImage] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CartoonFilterPreset.allCases) { preset in
                    FilterThumbnailView(
                        preset: preset,
                        thumbnail: thumbnails[preset.id],
                        isSelected: selectedFilter == preset
                    ) {
                        selectedFilter = preset
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .task(id: sourceImage?.hash) {
            await generateThumbnails()
        }
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnails() async {
        guard let image = sourceImage else { return }

        // Generate all thumbnails off the main thread.
        let newThumbnails: [String: UIImage] = await Task.detached(priority: .userInitiated) {
            var result: [String: UIImage] = [:]
            for preset in CartoonFilterPreset.allCases {
                result[preset.id] = CartoonFilter.thumbnail(from: image, preset: preset)
            }
            return result
        }.value

        thumbnails = newThumbnails
    }
}

// MARK: - Filter Thumbnail

private struct FilterThumbnailView: View {
    let preset: CartoonFilterPreset
    let thumbnail: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: preset.sfSymbol)
                            .font(.title3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray6))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

                Text(preset.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.rawValue) filter\(isSelected ? ", selected" : "")")
    }
}
