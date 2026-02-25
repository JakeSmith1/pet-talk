import SwiftUI

/// Displays a grid/list of saved projects with thumbnails.
/// Tapping a project loads it into the active PetTalkProject and navigates to the preview step.
struct ProjectListView: View {
    @EnvironmentObject private var project: PetTalkProject
    @ObservedObject var store: ProjectStore

    @State private var showDeleteConfirmation = false
    @State private var projectToDelete: SavedProject?
    @State private var errorMessage: String?
    @State private var showError = false

    /// Dismiss action for when this view is presented modally.
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    projectGrid
                }
            }
            .navigationTitle("My Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Project?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        deleteProject(project)
                    }
                }
                Button("Cancel", role: .cancel) {
                    projectToDelete = nil
                }
            } message: {
                if let project = projectToDelete {
                    Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Saved Projects")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Create a PetTalk video and save it\nto see it here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    private var projectGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.projects) { saved in
                    projectCard(saved)
                }
            }
            .padding()
        }
    }

    private func projectCard(_ saved: SavedProject) -> some View {
        Button {
            loadProject(saved)
        } label: {
            VStack(spacing: 8) {
                // Thumbnail.
                Group {
                    if let thumbnail = store.thumbnailImage(for: saved) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(.tertiarySystemBackground))
                            .aspectRatio(1, contentMode: .fill)
                            .overlay {
                                Image(systemName: "pawprint.fill")
                                    .font(.title)
                                    .foregroundStyle(.quaternary)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Name and date.
                VStack(spacing: 2) {
                    Text(saved.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(saved.modifiedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                loadProject(saved)
            } label: {
                Label("Open", systemImage: "folder.fill")
            }

            Button(role: .destructive) {
                projectToDelete = saved
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func loadProject(_ saved: SavedProject) {
        do {
            try store.load(saved, into: project)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteProject(_ saved: SavedProject) {
        do {
            try store.delete(saved)
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
            showError = true
        }
        projectToDelete = nil
    }
}
