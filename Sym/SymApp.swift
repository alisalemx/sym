import SwiftUI

@main
struct SymApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 440, minHeight: 380)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

