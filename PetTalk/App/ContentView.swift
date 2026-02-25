import SwiftUI

struct ContentView: View {
    @EnvironmentObject var project: PetTalkProject
    @EnvironmentObject var duetProject: DuetProject
    @StateObject private var projectStore = ProjectStore()
    @State private var showSettings = false
    @State private var showProjectList = false
    @State private var showSaveSheet = false
    @State private var isDuetMode = false

    var body: some View {
        NavigationStack {
            if isDuetMode {
                duetContent
            } else {
                soloContent
            }
        }
    }

    // MARK: - Solo Mode Content

    private var soloContent: some View {
        Group {
            TabView(selection: $project.currentStep) {
                PhotoPickerView()
                    .tag(PetTalkProject.Step.pickPhoto)

                AudioRecordView()
                    .tag(PetTalkProject.Step.recordAudio)

                PreviewView()
                    .tag(PetTalkProject.Step.preview)

                ExportShareView()
                    .tag(PetTalkProject.Step.export)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: project.currentStep)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if project.currentStep != .pickPhoto {
                        Button("Back") {
                            let raw = project.currentStep.rawValue
                            if raw > 0, let prev = PetTalkProject.Step(rawValue: raw - 1) {
                                project.currentStep = prev
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }

                            Button {
                                showProjectList = true
                            } label: {
                                Image(systemName: "folder")
                            }

                            Button {
                                isDuetMode = true
                            } label: {
                                Image(systemName: "person.2.fill")
                            }
                            .accessibilityLabel("Duet Mode")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if project.currentStep != .pickPhoto {
                            // Save project button (available when we have image + audio).
                            if project.image != nil && project.audioURL != nil {
                                Button {
                                    showSaveSheet = true
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                .disabled(project.currentStep == .export)
                            }

                            Button("Start Over") {
                                project.reset()
                            }
                            .disabled(project.currentStep == .export)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showProjectList) {
                ProjectListView(store: projectStore)
                    .environmentObject(project)
            }
            .sheet(isPresented: $showSaveSheet) {
                SaveProjectSheet(store: projectStore)
                    .environmentObject(project)
            }
        }
    }

    private var navigationTitle: String {
        switch project.currentStep {
        case .pickPhoto: return "Choose Pet Photo"
        case .recordAudio: return "Record Audio"
        case .preview: return "Preview"
        case .export: return "Export & Share"
        }
    }

    // MARK: - Duet Mode Content

    private var duetContent: some View {
        Group {
            switch duetProject.currentStep {
            case .setupLeft, .setupRight:
                DuetSetupView()
                    .environmentObject(duetProject)
            case .preview:
                DuetPreviewView()
                    .environmentObject(duetProject)
            case .export:
                DuetExportView()
                    .environmentObject(duetProject)
            }
        }
        .navigationTitle(duetNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if duetProject.currentStep != .setupLeft {
                    Button("Back") {
                        let raw = duetProject.currentStep.rawValue
                        if raw > 0, let prev = DuetStep(rawValue: raw - 1) {
                            duetProject.currentStep = prev
                        }
                    }
                } else {
                    Button {
                        isDuetMode = false
                    } label: {
                        Label("Solo Mode", systemImage: "person.fill")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start Over") {
                    duetProject.reset()
                }
                .disabled(duetProject.currentStep == .export)
            }
        }
    }

    private var duetNavigationTitle: String {
        duetProject.currentStep.title
    }
}
