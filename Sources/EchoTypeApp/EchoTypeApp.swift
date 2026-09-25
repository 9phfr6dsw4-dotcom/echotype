import AppKit
import SwiftUI

@main
@MainActor
struct EchoTypeApp: App {
    @NSApplicationDelegateAdaptor(EchoTypeApplicationDelegate.self) private var applicationDelegate
    @State private var runtime = EchoTypeRuntime()

    var body: some Scene {
        WindowGroup("EchoType") {
            ModelLibraryView()
                .environment(runtime)
                .navigationTitle("EchoType")
        }
        .defaultSize(width: 920, height: 760)
    }
}

@MainActor
final class EchoTypeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
