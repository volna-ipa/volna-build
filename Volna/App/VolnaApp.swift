import SwiftUI

@main
struct VolnaApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.settings)
                .environmentObject(environment.library)
                .task {
                    await environment.bootstrap()
                }
        }
    }
}
