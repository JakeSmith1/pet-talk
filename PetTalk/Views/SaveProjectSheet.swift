import SwiftUI

/// A sheet that allows the user to name and save the current project.
struct SaveProjectSheet: View {
    @EnvironmentObject private var project: PetTalkProject
    @ObservedObject var store: ProjectStore

    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isSaving = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Thumbnail preview.
                if let image = project.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 4)
                }

                // Name input.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("My Pet Video", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            saveProject()
                        }
                }
                .padding(.horizontal)

                // Save button.
                Button {
                    saveProject()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Project")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Save Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Pre-fill with existing project name if available.
                if let existingName = project.projectName, !existingName.isEmpty {
                    projectName = existingName
                }
                nameFieldFocused = true
            }
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - Actions

    private func saveProject() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let image = project.image,
              let audioURL = project.audioURL,
              let mouthRegion = project.mouthRegion else {
            errorMessage = "Missing project data. Please ensure you have a photo and audio."
            showError = true
            return
        }

        isSaving = true

        do {
            let saved = try store.save(
                name: trimmedName,
                image: image,
                audioURL: audioURL,
                mouthRegion: mouthRegion,
                pitchShift: project.pitchShift,
                existingId: project.savedProjectId
            )

            project.projectName = saved.name
            project.savedProjectId = saved.id
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
