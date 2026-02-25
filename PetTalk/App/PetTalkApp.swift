import SwiftUI

@main
struct PetTalkApp: App {
    @StateObject private var project = PetTalkProject()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
        }
    }
}
