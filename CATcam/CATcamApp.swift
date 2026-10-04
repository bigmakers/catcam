import SwiftUI

@main
struct CATcamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .task {
                    #if targetEnvironment(simulator)
                    await DemoRender.runIfRequested()
                    #endif
                }
        }
    }
}
