import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 0 foundation hook. Runtime startup belongs to Phase 1.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Phase 0 foundation hook. Runtime shutdown belongs to Phase 1.
    }
}
