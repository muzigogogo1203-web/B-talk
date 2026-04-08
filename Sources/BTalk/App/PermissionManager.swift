@preconcurrency import Foundation
import AppKit
import AVFoundation
@preconcurrency import ApplicationServices

@MainActor
final class PermissionManager: ObservableObject {
    @Published var microphoneGranted: Bool = false
    @Published var inputMonitoringGranted: Bool = false
    @Published var postEventGranted: Bool = false

    var allPermissionsGranted: Bool {
        microphoneGranted && inputMonitoringGranted && postEventGranted
    }

    func checkAllPermissions() {
        checkMicrophone()
        checkInputMonitoring()
        checkPostEvent()
    }

    // MARK: - Microphone

    func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    // MARK: - Input Monitoring (CGEvent tap listen)

    func checkInputMonitoring() {
        // CGPreflightListenEventAccess() is unreliable on macOS 14+.
        // Try creating a real tap to check — if it works, permission is granted.
        let preflight = CGPreflightListenEventAccess()
        if preflight {
            inputMonitoringGranted = true
            return
        }
        // Fallback: try a real tap
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            inputMonitoringGranted = true
        } else {
            inputMonitoringGranted = false
        }
    }

    func requestInputMonitoring() {
        CGRequestListenEventAccess()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            checkInputMonitoring()
        }
    }

    // MARK: - Post Event / Accessibility

    func checkPostEvent() {
        // AXIsProcessTrusted is more reliable than CGPreflightPostEventAccess
        // which was deprecated. Both check accessibility (needed for CGEvent.post).
        postEventGranted = AXIsProcessTrusted()
    }

    func requestPostEvent() {
        // Prompt user with system dialog
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        postEventGranted = trusted
        if !trusted {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                checkPostEvent()
            }
        }
    }

    // MARK: - Open System Settings

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
