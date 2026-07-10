import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// LaunchServices entry point: Finder double-click, Open With, drag to Dock.
    /// (With a single Window scene, SwiftUI does not deliver file opens via
    /// onOpenURL — the delegate route is the reliable one.)
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.open(urls)
    }

    /// Dock-icon click with the window closed: re-present it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppModel.shared.bringWindowFront()
            return false
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.prepareToTerminate() ? .terminateNow : .terminateCancel
    }
}
