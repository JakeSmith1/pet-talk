import Foundation
import UIKit

/// Manages saving, loading, listing, and deleting PetTalk projects on disk.
///
/// Projects are stored in `Application Support/PetTalkProjects/`, each in its own
/// UUID-named subdirectory containing the image, audio, thumbnail, and a `project.json`
/// metadata file.
@MainActor
final class ProjectStore: ObservableObject {

    // MARK: - Published State

    /// All saved projects, sorted by most recently modified first.
    @Published var projects: [SavedProject] = []

    /// Whether a save or load operation is in progress.
    @Published var isBusy: Bool = false

    // MARK: - Constants

    private static let rootDirectoryName = "PetTalkProjects"
    private static let thumbnailSize = CGSize(width: 300, height: 300)

    // MARK: - Initialization

    init() {
        loadProjectList()
    }

    // MARK: - Root Directory

    private var rootDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Self.rootDirectoryName, isDirectory: true)
    }

    private func projectDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func ensureRootDirectoryExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save

    /// Saves the current project state to disk.
    ///
    /// - Parameters:
    ///   - name: The user-provided project name.
    ///   - image: The pet photo.
    ///   - audioURL: The recorded/imported audio file URL.
    ///   - mouthRegion: The detected/adjusted mouth region.
    ///   - pitchShift: The pitch shift in semitones.
    ///   - existingId: If updating an existing project, pass its ID.
    /// - Returns: The saved project metadata.
    @discardableResult
    func save(
        name: String,
        image: UIImage,
        audioURL: URL,
        mouthRegion: MouthRegion,
        pitchShift: Float,
        existingId: UUID? = nil
    ) throws -> SavedProject {
        isBusy = true
        defer { isBusy = false }

        try ensureRootDirectoryExists()

        let projectId = existingId ?? UUID()
        let projectDir = projectDirectory(for: projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Save the image as JPEG.
        let imageFileName = "pet_image.jpg"
        let imageURL = projectDir.appendingPathComponent(imageFileName)
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            try jpegData.write(to: imageURL)
        }

        // Generate and save thumbnail.
        let thumbnailFileName = "thumbnail.jpg"
        let thumbnailURL = projectDir.appendingPathComponent(thumbnailFileName)
        let thumbnail = generateThumbnail(from: image)
        if let thumbData = thumbnail.jpegData(compressionQuality: 0.7) {
            try thumbData.write(to: thumbnailURL)
        }

        // Copy the audio file.
        let audioExtension = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
        let audioFileName = "audio.\(audioExtension)"
        let destAudioURL = projectDir.appendingPathComponent(audioFileName)
        // Remove existing audio file if updating.
        if FileManager.default.fileExists(atPath: destAudioURL.path) {
            try FileManager.default.removeItem(at: destAudioURL)
        }
        try FileManager.default.copyItem(at: audioURL, to: destAudioURL)

        // Create the metadata.
        let now = Date()
        let savedProject = SavedProject(
            id: projectId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existingId != nil
                ? (projects.first(where: { $0.id == projectId })?.createdAt ?? now)
                : now,
            modifiedAt: now,
            imageFileName: imageFileName,
            audioFileName: audioFileName,
            mouthRegion: CodableMouthRegion(from: mouthRegion),
            pitchShift: pitchShift,
            thumbnailFileName: thumbnailFileName
        )

        // Write metadata JSON.
        let metadataURL = projectDir.appendingPathComponent(SavedProject.metadataFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(savedProject)
        try data.write(to: metadataURL)

        // Update the in-memory list.
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index] = savedProject
        } else {
            projects.insert(savedProject, at: 0)
        }
        sortProjects()

        return savedProject
    }

    // MARK: - Load

    /// Loads a saved project's assets into the given PetTalkProject.
    ///
    /// - Parameters:
    ///   - savedProject: The saved project metadata.
    ///   - project: The live PetTalkProject to populate.
    func load(_ savedProject: SavedProject, into project: PetTalkProject) throws {
        isBusy = true
        defer { isBusy = false }

        let projectDir = projectDirectory(for: savedProject.id)

        // Load image.
        let imageURL = projectDir.appendingPathComponent(savedProject.imageFileName)
        guard let imageData = try? Data(contentsOf: imageURL),
              let image = UIImage(data: imageData) else {
            throw ProjectStoreError.imageLoadFailed
        }

        // Locate audio file.
        let audioURL = projectDir.appendingPathComponent(savedProject.audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ProjectStoreError.audioLoadFailed
        }

        // Copy audio to a temporary location so the project can manage its lifecycle independently.
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audioURL.pathExtension)
        try FileManager.default.copyItem(at: audioURL, to: tempAudioURL)

        // Populate the project.
        project.image = image
        project.mouthRegion = savedProject.mouthRegion.toMouthRegion()
        project.audioURL = tempAudioURL
        project.pitchShift = savedProject.pitchShift
        project.projectName = savedProject.name
        project.savedProjectId = savedProject.id
        project.exportedVideoURL = nil
        project.processedAudioURL = nil
        project.amplitudes = []
        project.currentStep = .preview
    }

    // MARK: - Delete

    /// Deletes a saved project and its files from disk.
    func delete(_ savedProject: SavedProject) throws {
        let projectDir = projectDirectory(for: savedProject.id)
        if FileManager.default.fileExists(atPath: projectDir.path) {
            try FileManager.default.removeItem(at: projectDir)
        }
        projects.removeAll { $0.id == savedProject.id }
    }

    /// Deletes multiple projects at the given index set.
    func delete(at offsets: IndexSet) throws {
        let toDelete = offsets.map { projects[$0] }
        for project in toDelete {
            try self.delete(project)
        }
    }

    // MARK: - List

    /// Reloads the project list from disk.
    func loadProjectList() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootDirectory.path) else {
            projects = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [SavedProject] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            projects = []
            return
        }

        for dir in contents {
            let metadataURL = dir.appendingPathComponent(SavedProject.metadataFileName)
            guard let data = try? Data(contentsOf: metadataURL),
                  let project = try? decoder.decode(SavedProject.self, from: data) else {
                continue
            }
            loaded.append(project)
        }

        projects = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Thumbnails

    /// Returns the thumbnail image for a saved project, or nil if unavailable.
    func thumbnailImage(for project: SavedProject) -> UIImage? {
        let url = projectDirectory(for: project.id)
            .appendingPathComponent(project.thumbnailFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Private

    private func sortProjects() {
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    private func generateThumbnail(from image: UIImage) -> UIImage {
        let size = Self.thumbnailSize
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let aspect = image.size.width / image.size.height
            let targetRect: CGRect
            if aspect > 1 {
                let height = size.height
                let width = height * aspect
                targetRect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
            } else {
                let width = size.width
                let height = width / aspect
                targetRect = CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height)
            }
            image.draw(in: targetRect)
        }
    }
}

// MARK: - Errors

enum ProjectStoreError: LocalizedError {
    case imageLoadFailed
    case audioLoadFailed

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Could not load the saved project image."
        case .audioLoadFailed:
            return "Could not locate the saved project audio file."
        }
    }
}
