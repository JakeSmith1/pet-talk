import SwiftUI

// MARK: - Accessory Picker View

/// A category-based grid for selecting multiple accessories.
struct AccessoryPickerView: View {
    @Binding var selectedAccessories: [AccessoryPlacement]

    @State private var activeCategory: Accessory.Category = .hats

    var body: some View {
        VStack(spacing: 12) {
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Accessory.Category.allCases) { category in
                        Button {
                            activeCategory = category
                        } label: {
                            Label(category.rawValue, systemImage: category.sfSymbolHeader)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(activeCategory == category ? Color.accentColor : Color(.systemGray5))
                                )
                                .foregroundStyle(activeCategory == category ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            // Accessory grid
            let items = Accessory.accessories(in: activeCategory)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                ForEach(items) { accessory in
                    AccessoryCell(
                        accessory: accessory,
                        isSelected: isSelected(accessory)
                    ) {
                        toggleAccessory(accessory)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isSelected(_ accessory: Accessory) -> Bool {
        selectedAccessories.contains { $0.accessory.id == accessory.id }
    }

    private func toggleAccessory(_ accessory: Accessory) {
        if let index = selectedAccessories.firstIndex(where: { $0.accessory.id == accessory.id }) {
            selectedAccessories.remove(at: index)
        } else {
            selectedAccessories.append(AccessoryPlacement(accessory: accessory))
        }
    }
}

// MARK: - Accessory Cell

private struct AccessoryCell: View {
    let accessory: Accessory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: accessory.sfSymbol)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(accessory.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessory.name), \(isSelected ? "selected" : "not selected")")
    }
}
