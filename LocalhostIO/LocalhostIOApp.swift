import SwiftUI
import AppKit

@main
struct LocalhostIOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 780, minHeight: 480)
                .onAppear { appDelegate.appState = appState }
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Refresh Running Servers") {
                    appState.refreshRunning()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Handles the quit flow so servers IO launched aren't silently orphaned.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.hasManagedServersRunning else { return .terminateNow }

        let count = appState.managedRunningCount
        let noun = count == 1 ? "server" : "servers"

        let alert = NSAlert()
        alert.messageText = "Stop running \(noun) before quitting?"
        alert.informativeText = "IO: localhost started \(count) \(noun) that \(count == 1 ? "is" : "are") still running. "
            + "If you leave \(count == 1 ? "it" : "them") running, \(count == 1 ? "it" : "they") will keep running in the background after IO quits."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Leave Running")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            appState.stopAllManaged()
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
