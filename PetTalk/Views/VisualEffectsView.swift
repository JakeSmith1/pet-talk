import SwiftUI

// MARK: - Visual Effects Panel

/// A collapsible panel containing all four visual effects feature sections:
/// Eye Animation, Accessories, Background Replacement, and Cartoon Filter.
struct VisualEffectsView: View {
    @EnvironmentObject private var project: PetTalkProject

    @State private var isEyeAnimationExpanded = false
    @State private var isAccessoriesExpanded = false
    @State private var isBackgroundExpanded = false
    @State private var isFilterExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader("Eye Animation", systemImage: "eye", isExpanded: $isEyeAnimationExpanded)

            if isEyeAnimationExpanded {
                eyeAnimationSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Divider()

            sectionHeader("Accessories", systemImage: "theatermask.and.paintbrush", isExpanded: $isAccessoriesExpanded)

            if isAccessoriesExpanded {
                AccessoryPickerView(selectedAccessories: $project.selectedAccessories)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Divider()

            sectionHeader("Background", systemImage: "photo.artframe", isExpanded: $isBackgroundExpanded)

            if isBackgroundExpanded {
                backgroundSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Divider()

            sectionHeader("Filter", systemImage: "camera.filters", isExpanded: $isFilterExpanded)

            if isFilterExpanded {
                FilterPickerView(selectedFilter: $project.selectedFilter, sourceImage: project.image)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(isExpanded.wrappedValue ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to \(isExpanded.wrappedValue ? "collapse" : "expand")")
    }

    // MARK: - Eye Animation Section

    private var eyeAnimationSection: some View {
        Toggle("Enable Eye Animation", isOn: $project.enableEyeAnimation)
            .font(.subheadline)
            .tint(.accentColor)
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        BackgroundPickerView(
            selectedBackground: $project.selectedBackground,
            customBackgroundImage: $project.customBackgroundImage
        )
    }
}
