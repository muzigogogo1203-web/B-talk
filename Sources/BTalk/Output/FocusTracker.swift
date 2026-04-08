import AppKit

@MainActor
final class FocusTracker {
    private var sourceApp: NSRunningApplication?

    func recordFrontmostApp() {
        sourceApp = NSWorkspace.shared.frontmostApplication
    }

    func activateSourceApp() async {
        guard let app = sourceApp else { return }
        app.activate()
        // Wait for activation to complete
        try? await Task.sleep(nanoseconds: 150_000_000) // ~150ms
    }

    var sourceAppName: String? {
        sourceApp?.localizedName
    }
}
