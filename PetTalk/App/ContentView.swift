import SwiftUI

struct ContentView: View {
    @EnvironmentObject var project: PetTalkProject

    var body: some View {
        NavigationStack {
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
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if project.currentStep != .pickPhoto {
                        Button("Start Over") {
                            project.reset()
                        }
                    }
                }
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
}
