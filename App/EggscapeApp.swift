import SwiftUI

@main
struct EggscapeApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
        }
    }
}
