import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct FlashFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager: DownloadManager

    init() {
        if CommandLine.arguments.contains("--self-test") {
            let success = SelfCheck.run()
            fflush(stdout)
            exit(success ? 0 : 1)
        }
        _manager = StateObject(wrappedValue: DownloadManager())
    }

    var body: some Scene {
        WindowGroup("FlashFlow", id: "main") {
            ContentView()
                .environmentObject(manager)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { EmptyView() }
        }

        MenuBarExtra("FlashFlow", systemImage: "bolt.horizontal.circle.fill") {
            MenuBarContent()
                .environmentObject(manager)
        }
    }
}
