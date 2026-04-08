import AppKit
import SwiftUI
import CoreGraphics
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    let permissionManager = PermissionManager()
    let focusTracker = FocusTracker()
    private let audioCapture = AudioCaptureManager()
    private lazy var pasteManager = CursorPasteManager(focusTracker: focusTracker)
    private var floatingWindow: FloatingWindowController?

    var sttProvider: (any STTProvider)?
    var llmProvider: (any LLMProvider)?

    // Separate reference for audio-thread access (nonisolated — written only during setup)
    nonisolated(unsafe) private var appleSTTRef: AppleSTTProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate hotkey config to v2: reset to Right⌘Space (clears any accidentally-set keys)
        if UserDefaults.standard.integer(forKey: "hotkey.configVersion") < 2 {
            UserDefaults.standard.set(49, forKey: "hotkey.keyCode")        // Space
            UserDefaults.standard.set(1048576, forKey: "hotkey.modifiers") // .maskCommand
            UserDefaults.standard.set(true, forKey: "hotkey.rightCommandOnly")
            UserDefaults.standard.set(2, forKey: "hotkey.configVersion")
        }

        Task { @MainActor in
            permissionManager.checkAllPermissions()
            await requestMissingPermissions()
            setupFloatingWindow()
            setupAudioCapture()
            setupHotKey()
            reloadProviders()

            // Show Quick Setup on first launch
            if !UserDefaults.standard.bool(forKey: "quickSetup.completed") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showQuickSetupWindow()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .hotKeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadHotKey() }
        }
        NotificationCenter.default.addObserver(
            forName: .rawHotKeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadRawPasteHotKey() }
        }
        NotificationCenter.default.addObserver(
            forName: .voiceCodeStopRecording, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.toggleRecording() }
        }
        NotificationCenter.default.addObserver(
            forName: .voiceCodePasteAtCursor, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pasteResultAtCursor()
                self?.hideFloatingWindow()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .voiceCodePasteRawAtCursor, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pasteRawAtCursor()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .voiceCodeSaveToLibrary, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let item = InspirationItem(
                    rawTranscript: self.appState.finalTranscript,
                    structuredContent: self.appState.structuredResult,
                    sourceApp: nil
                )
                LibraryStore.shared.add(item)
                self.appState.reset()
                self.hideFloatingWindow()
            }
        }
    }

    func reloadProviders() {
        let settings = AppSettings.shared
        let provider = STTProviderFactory.make(from: settings.buildSTTConfig())
        sttProvider = provider
        appleSTTRef = provider as? AppleSTTProvider
        llmProvider = settings.buildLLMProvider()
    }

    private func setupFloatingWindow() {
        floatingWindow = FloatingWindowController(appState: appState)
    }

    private func setupAudioCapture() {
        audioCapture.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.appState.audioLevel = level
            }
        }
        audioCapture.onAudioData = { [weak self] data in
            Task { @MainActor in
                try? await self?.sttProvider?.sendAudioData(data)
            }
        }
        // Raw buffer for Apple STT (SFSpeechAudioBufferRecognitionRequest needs AVAudioPCMBuffer)
        audioCapture.onAudioBuffer = { [weak self] buffer in
            // appleSTTRef is nonisolated(unsafe) — safe to read from audio thread
            // because it is only written on main actor before recording starts
            self?.appleSTTRef?.sendAudioBuffer(buffer)
        }
    }

    private func setupHotKey() {
        let settings = AppSettings.shared
        let mgr = GlobalHotKeyManager.shared
        let success = mgr.register(
            id: "main",
            modifiers: CGEventFlags(rawValue: UInt64(settings.hotKeyModifiers)),
            keyCode: CGKeyCode(settings.hotKeyCode),
            rightCommandOnly: settings.hotKeyRightCommandOnly
        ) { [weak self] in
            self?.handleHotKeyPressed()
        }
        if !success {
            showAlert(
                "Hotkey Not Available",
                message: "Could not register global hotkey — Input Monitoring permission may not be fully active.\n\nIn System Settings → Privacy & Security → Input Monitoring, toggle B-talk OFF then ON, then restart the app.\n\nYou can still use menu bar → Start Recording in the meantime."
            )
        }

        // Register raw paste hotkey if configured
        registerRawPasteHotKeyIfNeeded()
    }

    private func registerRawPasteHotKeyIfNeeded() {
        let settings = AppSettings.shared
        let mgr = GlobalHotKeyManager.shared
        if settings.rawPasteKeyCode != 0 {
            mgr.register(
                id: "rawPaste",
                modifiers: CGEventFlags(rawValue: UInt64(settings.rawPasteModifiers)),
                keyCode: CGKeyCode(settings.rawPasteKeyCode),
                rightCommandOnly: settings.rawPasteRightCommandOnly
            ) { [weak self] in
                Task { @MainActor in
                    await self?.pasteRawAtCursor()
                }
            }
        } else {
            mgr.unregister(id: "rawPaste")
        }
    }

    func reloadHotKey() {
        let settings = AppSettings.shared
        GlobalHotKeyManager.shared.update(
            id: "main",
            modifiers: CGEventFlags(rawValue: UInt64(settings.hotKeyModifiers)),
            keyCode: CGKeyCode(settings.hotKeyCode),
            rightCommandOnly: settings.hotKeyRightCommandOnly
        )
    }

    func reloadRawPasteHotKey() {
        registerRawPasteHotKeyIfNeeded()
    }

    private func handleHotKeyPressed() {
        switch appState.mode {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .showingResult:
            Task {
                await pasteResultAtCursor()
                hideFloatingWindow()
            }
        case .showingError:
            appState.reset()
        default: break
        }
    }

    private func startRecording() {
        // Request microphone permission if not yet granted
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if granted { self.startRecording() }
                else { self.showAlert("Microphone Required", message: "Please grant microphone access in System Settings → Privacy → Microphone.") }
            }
            return
        }
        if micStatus == .denied || micStatus == .restricted {
            showAlert("Microphone Denied", message: "Please grant microphone access in System Settings → Privacy & Security → Microphone.")
            return
        }

        // Reload providers before starting so latest settings/API keys are picked up
        reloadProviders()
        focusTracker.recordFrontmostApp()
        appState.toggleRecording()
        floatingWindow?.showPanel()

        do {
            try audioCapture.startCapture()
        } catch {
            appState.reset()
            showAlert("Microphone Error", message: error.localizedDescription)
            return
        }

        if let stt = sttProvider {
            Task {
                do {
                    let stream = try await stt.startStreaming(language: "")
                    for await result in stream {
                        appState.interimTranscript = result.text
                    }
                } catch {
                    // Only show STT stream errors while still recording
                    if appState.mode == .recording {
                        appState.setError("STT error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func stopRecording() {
        appState.toggleRecording() // -> .finalizing
        audioCapture.stopCapture()

        // Capture the active STT provider BEFORE any reload so we keep the live session
        let activeStt = sttProvider
        // Reload LLM provider only (STT is already running, replacing it would lose the transcript)
        llmProvider = AppSettings.shared.buildLLMProvider()

        Task {
            if let stt = activeStt {
                do {
                    let transcript = try await stt.stopStreaming()

                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        appState.setError("未识别到语音，请重试")
                        return
                    }

                    // Clean noise and assess quality
                    let (cleaned, isLowQuality) = analyzeTranscript(transcript)
                    appState.transcriptQualityLow = isLowQuality

                    guard !cleaned.isEmpty else {
                        appState.setError("识别内容为噪声，请重试")
                        return
                    }

                    appState.setStructuring(transcript: cleaned)

                    if let llm = llmProvider {
                        appState.mode = .structuring
                        let result = try await llm.structure(transcript: cleaned)
                        let finalResult = result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? cleaned
                            : result
                        appState.setResult(finalResult)
                    } else {
                        // LLM not configured — surface raw transcript and explain
                        appState.setError("LLM未配置：请在设置 → LLM 中填入 API Key 并点击 Save。\n\n原始转写：\(transcript)")
                    }
                } catch {
                    appState.setError("Processing error: \(error.localizedDescription)")
                }
            } else {
                // Demo mode when no STT configured
                simulateProcessing()
            }
        }
    }

    private func simulateProcessing() {
        Task {
            appState.setTranscribing()
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let demo = "把 login function 的 return type 改成 Promise<User>，然后加上 error handling"
            appState.setStructuring(transcript: demo)
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let result = """
            1. [Auth Module] 修改 `login` 函数
               - 返回类型从 `void` 改为 `Promise<User>`

            2. [Auth Module] 添加错误处理
               - 添加 try-catch 包裹登录逻辑
               - 返回合适的错误响应
            """
            appState.setResult(result)
        }
    }

    // MARK: - Transcript quality analysis

    /// Clean common STT noise and assess transcript quality.
    /// Returns (cleaned text, isLowQuality).
    private func analyzeTranscript(_ raw: String) -> (String, Bool) {
        var text = raw

        // Remove leading digit noise (e.g. "1234567 检查..." from STT artifacts)
        text = text.replacingOccurrences(
            of: #"^\s*[\d\s]{6,}\s*"#,
            with: "",
            options: .regularExpression
        )

        // Remove repeated words/phrases (e.g. "好好好好" or "对对对")
        text = text.replacingOccurrences(
            of: #"(.)\1{3,}"#,
            with: "$1",
            options: .regularExpression
        )

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Quality heuristics
        let digitCount = trimmed.filter(\.isNumber).count
        let totalCount = trimmed.count
        let digitRatio = totalCount > 0 ? Double(digitCount) / Double(totalCount) : 0
        let tooShort = totalCount < 4
        let tooManyDigits = digitRatio > 0.5 && totalCount > 3

        let isLow = tooShort || tooManyDigits

        return (trimmed, isLow)
    }

    // MARK: - Paste at cursor action (called from FloatingContentView)

    func pasteResultAtCursor() async {
        let text = appState.structuredResult
        guard !text.isEmpty else { return }
        await pasteManager.pasteAtCursor(text)
        appState.reset()
    }

    // MARK: - Paste raw transcript at cursor

    func pasteRawAtCursor() async {
        guard appState.mode == .showingResult else { return }
        let raw = appState.finalTranscript
        guard !raw.isEmpty else { return }
        await pasteManager.pasteAtCursor(raw)
        appState.reset()
        hideFloatingWindow()
    }

    // MARK: - Permission auto-request on launch

    private func requestMissingPermissions() async {
        if !permissionManager.microphoneGranted {
            await permissionManager.requestMicrophone()
        }
        if !permissionManager.inputMonitoringGranted {
            permissionManager.requestInputMonitoring()
        }
        if !permissionManager.postEventGranted {
            permissionManager.requestPostEvent()
        }
        permissionManager.checkAllPermissions()
    }

    // MARK: - Public

    func toggleRecording() { handleHotKeyPressed() }
    func showFloatingWindow() { floatingWindow?.showPanel() }
    func hideFloatingWindow() { floatingWindow?.hidePanel() }

    // MARK: - Quick Setup

    private var quickSetupWindow: NSWindow?

    func showQuickSetupWindow() {
        if let existing = quickSetupWindow, existing.isVisible { return }

        let setupView = QuickSetupView()
        let hostingView = NSHostingView(rootView: setupView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "B-talk Quick Setup"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        quickSetupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
