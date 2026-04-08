import AppKit
import CoreGraphics

/// Pastes text at the cursor position in the frontmost app.
/// Requires Post Event (Accessibility) permission: CGPreflightPostEventAccess().
@MainActor
final class CursorPasteManager {
    private let focusTracker: FocusTracker

    init(focusTracker: FocusTracker) {
        self.focusTracker = focusTracker
    }

    /// Paste text at the cursor in the source application (recorded before recording started).
    func pasteAtCursor(_ text: String) async {
        // 1. Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item -> (types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data]) in
            let types = item.types
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in types {
                if let d = item.data(forType: type) {
                    data[type] = d
                }
            }
            return (types: types, data: data)
        }

        // 2. Write new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Activate the source application
        await focusTracker.activateSourceApp()

        // 4. Simulate Cmd+V (paste)
        postCmdV()

        // 5. Wait for paste to complete, then restore original clipboard
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        restoreClipboard(pasteboard: pasteboard, savedItems: savedItems)
    }

    private func postCmdV() {
        guard CGPreflightPostEventAccess() else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        // V key: keycode 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }

    private func restoreClipboard(
        pasteboard: NSPasteboard,
        savedItems: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])]?
    ) {
        guard let savedItems = savedItems, !savedItems.isEmpty else { return }

        pasteboard.clearContents()
        for savedItem in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in savedItem.data {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
