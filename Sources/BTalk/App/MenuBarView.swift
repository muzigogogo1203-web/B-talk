import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    private var hotkeyLabel: String {
        let s = AppSettings.shared
        return hotKeyDisplayString(
            keyCode: s.hotKeyCode,
            modifiers: s.hotKeyModifiers,
            rightCommandOnly: s.hotKeyRightCommandOnly
        )
    }

    var body: some View {
        Group {
            if appDelegate.appState.isRecording {
                Button("Stop Recording (\(hotkeyLabel))") {
                    appDelegate.toggleRecording()
                }
            } else {
                Button("Start Recording (\(hotkeyLabel))") {
                    appDelegate.toggleRecording()
                }
                .disabled(appDelegate.appState.isProcessing)
            }

            Divider()

            Button("Show Window") {
                appDelegate.showFloatingWindow()
            }

            Button("Library") {
                openWindow(id: "library")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Permissions") {
                showPermissionStatus()
            }

            SettingsLink {
                Text("Settings...")
            }

            Divider()

            Button("Quit B-talk") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func showPermissionStatus() {
        let pm = appDelegate.permissionManager
        pm.checkAllPermissions()

        let alert = NSAlert()
        alert.messageText = "Permission Status"
        alert.informativeText = """
        Microphone: \(pm.microphoneGranted ? "✓" : "✗ Not Granted")
        Input Monitoring: \(pm.inputMonitoringGranted ? "✓" : "✗ Not Granted")
        Accessibility (Post Event): \(pm.postEventGranted ? "✓" : "✗ Not Granted")

        Open Settings to grant missing permissions.
        Note: Permissions must be re-toggled after each rebuild.
        """
        alert.addButton(withTitle: "OK")
        if !pm.allPermissionsGranted {
            alert.addButton(withTitle: "Open Settings")
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if !pm.microphoneGranted { pm.openMicrophoneSettings() }
            else if !pm.inputMonitoringGranted { pm.openInputMonitoringSettings() }
            else { pm.openAccessibilitySettings() }
        }
    }
}
