import SwiftUI

@main
struct PetTalkApp: App {
    @StateObject private var project = PetTalkProject()
    @StateObject private var duetProject = DuetProject()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
                .environmentObject(duetProject)
        }
    }
}
