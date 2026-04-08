import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    var body: some View {
        TabView {
            STTSettingsView()
                .tabItem {
                    Label("Speech", systemImage: "mic")
                }

            LLMSettingsView()
                .tabItem {
                    Label("LLM", systemImage: "brain")
                }

            PromptSettingsView()
                .tabItem {
                    Label("Prompt", systemImage: "text.quote")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            PermissionSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Record / Stop")
                    Spacer()
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers,
                        rightCommandOnly: $settings.hotKeyRightCommandOnly
                    )
                }
                Text("Press the button and type your desired key combination. Escape cancels.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Paste Raw Text")
                    Spacer()
                    HotKeyRecorder(
                        keyCode: $settings.rawPasteKeyCode,
                        modifiers: $settings.rawPasteModifiers,
                        rightCommandOnly: $settings.rawPasteRightCommandOnly,
                        notificationName: .rawHotKeyDidChange
                    )
                }
                Text("Optional. Leave unset to use Esc only in result window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Default Output") {
                Picker("After confirmation", selection: $settings.defaultOutput) {
                    Text("Always ask").tag("ask")
                    Text("Paste at cursor").tag("paste")
                    Text("Save to library").tag("library")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Recorder

struct HotKeyRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var rightCommandOnly: Bool
    var notificationName: Notification.Name = .hotKeyDidChange

    @State private var isRecording = false
    @State private var monitor: Any?

    var label: String {
        if isRecording { return "Press key combo…" }
        if keyCode == 0 { return "Not Set" }
        return hotKeyDisplayString(keyCode: keyCode, modifiers: modifiers, rightCommandOnly: rightCommandOnly)
    }

    var body: some View {
        Button(label) {
            isRecording ? stopRecording() : startRecording()
        }
        .foregroundColor(isRecording ? .red : (keyCode == 0 ? .secondary : .primary))
        .font(.system(.body, design: .monospaced))
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
        .onChange(of: keyCode) { _ in notifyReload() }
        .onChange(of: modifiers) { _ in notifyReload() }
        .onChange(of: rightCommandOnly) { _ in notifyReload() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape → cancel
                self.stopRecording()
                return event
            }
            // Ignore standalone modifier keypresses (Cmd, Shift, etc.)
            let ignoredKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !ignoredKeyCodes.contains(event.keyCode) else { return event }

            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            self.keyCode = Int(event.keyCode)
            self.modifiers = Int(mods.rawValue)
            // NX_DEVICERCMDKEYMASK = 0x10
            self.rightCommandOnly = mods.contains(.command) && (event.modifierFlags.rawValue & 0x10) != 0
            self.stopRecording()
            return nil // consume
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func notifyReload() {
        NotificationCenter.default.post(name: notificationName, object: nil)
    }
}

extension Notification.Name {
    static let hotKeyDidChange = Notification.Name("BTalk.hotKeyDidChange")
    static let rawHotKeyDidChange = Notification.Name("BTalk.rawHotKeyDidChange")
}

// MARK: - Hotkey Display Formatting

func hotKeyDisplayString(keyCode: Int, modifiers: Int, rightCommandOnly: Bool) -> String {
    var parts = ""
    let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    if mods.contains(.control)  { parts += "⌃" }
    if mods.contains(.option)   { parts += "⌥" }
    if mods.contains(.shift)    { parts += "⇧" }
    if mods.contains(.command)  { parts += rightCommandOnly ? "Right⌘" : "⌘" }
    parts += keyCodeDisplayName(keyCode)
    return parts
}

private func keyCodeDisplayName(_ keyCode: Int) -> String {
    switch keyCode {
    case 49: return "Space"
    case 36: return "↩"
    case 48: return "⇥"
    case 51: return "⌫"
    case 53: return "⎋"
    case 126: return "↑"
    case 125: return "↓"
    case 123: return "←"
    case 124: return "→"
    case 115: return "Home"
    case 119: return "End"
    case 116: return "PgUp"
    case 121: return "PgDn"
    case 122: return "F1";  case 120: return "F2";  case 99: return "F3"
    case 118: return "F4";  case 96:  return "F5";  case 97: return "F6"
    case 98:  return "F7";  case 100: return "F8";  case 101: return "F9"
    case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
    default:
        // Map ANSI key codes to characters
        let map: [Int: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",
            20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",
            29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",
            39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
        ]
        return map[keyCode] ?? "(\(keyCode))"
    }
}

// MARK: - Permission Settings

struct PermissionSettingsView: View {
    @StateObject private var pm = PermissionManager()

    private var currentHotKeyLabel: String {
        let s = AppSettings.shared
        return hotKeyDisplayString(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers, rightCommandOnly: s.hotKeyRightCommandOnly)
    }

    var body: some View {
        Form {
            Section("Required Permissions") {
                PermissionRow(
                    title: "Microphone",
                    description: "Record audio for speech recognition",
                    granted: pm.microphoneGranted,
                    systemImage: "mic.fill"
                ) {
                    pm.openMicrophoneSettings()
                }

                PermissionRow(
                    title: "Input Monitoring",
                    description: "Listen for global hotkey (\(currentHotKeyLabel))",
                    granted: pm.inputMonitoringGranted,
                    systemImage: "keyboard"
                ) {
                    pm.openInputMonitoringSettings()
                }

                PermissionRow(
                    title: "Accessibility (Post Event)",
                    description: "Simulate Cmd+V to paste at cursor",
                    granted: pm.postEventGranted,
                    systemImage: "figure.wave"
                ) {
                    pm.openAccessibilitySettings()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { pm.checkAllPermissions() }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let systemImage: String
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(granted ? .green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") { openSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
