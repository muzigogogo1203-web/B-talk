import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let voiceCodeStopRecording = Notification.Name("BTalk.stopRecording")
    static let voiceCodePasteAtCursor = Notification.Name("BTalk.pasteAtCursor")
    static let voiceCodePasteRawAtCursor = Notification.Name("BTalk.pasteRawAtCursor")
    static let voiceCodeSaveToLibrary = Notification.Name("BTalk.saveToLibrary")
}

private class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = .clear
    }
}

// MARK: - Controller

@MainActor
final class FloatingWindowController {
    private var panel: NSPanel?
    private let appState: AppState
    private var modeObserver: AnyCancellable?

    private let barWidth: CGFloat = 420
    private let compactHeight: CGFloat = 52
    private let expandedHeight: CGFloat = 220

    init(appState: AppState) {
        self.appState = appState
        modeObserver = appState.$mode.receive(on: RunLoop.main).sink { [weak self] mode in
            guard let self = self, self.panel?.isVisible == true else { return }
            if mode == .idle {
                self.hidePanel()
            } else {
                self.repositionPanel(animated: true)
            }
        }
    }

    func showPanel() {
        if panel == nil { createPanel() }
        repositionPanel(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func togglePanel() {
        if let panel, panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func targetHeight() -> CGFloat {
        switch appState.mode {
        case .showingResult, .showingError: return expandedHeight
        default: return compactHeight
        }
    }

    private func repositionPanel(animated: Bool) {
        guard let panel, let screen = NSScreen.main else { return }
        let h = targetHeight()
        let sf = screen.visibleFrame
        let x = sf.minX + (sf.width - barWidth) / 2
        let y = sf.minY + sf.height * 0.25
        let newFrame = NSRect(x: x, y: y, width: barWidth, height: h)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: false)
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: barWidth, height: compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Use a clear NSView as contentView — SwiftUI handles the blur + rounded clip.
        // Avoids panel-background bleed-through at corners when using NSVisualEffectView directly.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let contentView = FloatingContentView(appState: appState)
        let hostingView = FirstMouseHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container
        self.panel = panel
    }
}

// MARK: - Content View

struct FloatingContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            switch appState.mode {
            case .idle:          idleBar
            case .recording:     recordingBar
            case .finalizing, .transcribing: processingBar(icon: "waveform", label: "Transcribing…")
            case .structuring:   processingBar(icon: "brain", label: "Structuring…")
            case .showingResult: resultCard
            case .showingError:  errorCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // SwiftUI-native blur + round clip — avoids NSPanel background bleed at corners
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
    }

    // MARK: Idle bar

    private var idleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            let s = AppSettings.shared
            let hk = hotKeyDisplayString(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers, rightCommandOnly: s.hotKeyRightCommandOnly)
            Text("Press \(hk) or click")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .voiceCodeStopRecording, object: nil)
            } label: {
                Text("Start")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.blue))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Recording bar

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)

            Text("Recording")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: i, total: 16))
                        .frame(width: 2.5, height: barHeight(for: i, total: 16))
                }
            }
            .frame(height: 24)
            .animation(.easeInOut(duration: 0.1), value: appState.audioLevel)

            if !appState.interimTranscript.isEmpty {
                Text(appState.interimTranscript)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 6)

            Button {
                NotificationCenter.default.post(name: .voiceCodeStopRecording, object: nil)
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
    }

    // MARK: Processing bar

    private func processingBar(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            if !appState.finalTranscript.isEmpty {
                Text(appState.finalTranscript)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @State private var showingRaw = false

    // MARK: Result card (expanded)

    private var resultCard: some View {
        VStack(spacing: 0) {
            // Header strip
            HStack(spacing: 8) {
                Circle().fill(appState.transcriptQualityLow ? .orange : .green)
                    .frame(width: 6, height: 6)

                if appState.transcriptQualityLow {
                    Text("识别质量较低")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Text("Result")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                // Toggle raw/structured view
                if !appState.finalTranscript.isEmpty {
                    Button {
                        showingRaw.toggle()
                    } label: {
                        Text(showingRaw ? "整理" : "原文")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    appState.reset()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 36)

            Divider().opacity(0.4)

            // Transcript text — toggle between structured and raw
            ScrollView {
                Text(showingRaw ? appState.finalTranscript : appState.structuredResult)
                    .font(.system(size: 12))
                    .foregroundStyle(showingRaw ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 130)

            Divider().opacity(0.4)

            // Action buttons + raw paste hint
            HStack(spacing: 6) {
                actionButton("Paste at Cursor", icon: "doc.on.clipboard", primary: true) {
                    NotificationCenter.default.post(name: .voiceCodePasteAtCursor, object: nil)
                }
                actionButton("Copy", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.structuredResult, forType: .string)
                }
                actionButton("Save", icon: "tray.and.arrow.down") {
                    NotificationCenter.default.post(name: .voiceCodeSaveToLibrary, object: nil)
                }

                Spacer()

                Text("⎋ 粘贴原文")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                // Hidden Esc button to paste raw transcript
                Button {
                    NotificationCenter.default.post(name: .voiceCodePasteRawAtCursor, object: nil)
                } label: {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: Error card

    private var errorCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text("Error")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    appState.reset()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 36)

            Divider().opacity(0.4)

            ScrollView {
                Text(appState.errorMessage ?? "Unknown error")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 130)

            Divider().opacity(0.4)

            HStack {
                actionButton("Retry", icon: "arrow.clockwise", primary: true) {
                    appState.reset()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func actionButton(_ label: String, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(primary ? Capsule().fill(Color.accentColor) : Capsule().fill(Color.clear))
                .foregroundColor(primary ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Waveform helpers

    private func barColor(for i: Int, total: Int) -> Color {
        Float(i) / Float(total) < appState.audioLevel ? .red : .gray.opacity(0.25)
    }

    private func barHeight(for i: Int, total: Int) -> CGFloat {
        Float(i) / Float(total) < appState.audioLevel
            ? CGFloat.random(in: 6...20)
            : 3
    }
}
