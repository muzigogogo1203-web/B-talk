import SwiftUI

struct QuickSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = AppSettings.shared
    @State private var selectedPreset: SetupPreset?
    @State private var step: SetupStep = .choosePreset

    enum SetupStep {
        case choosePreset
        case apiKeys
        case done
    }

    enum SetupPreset: String, CaseIterable {
        case chineseGeneral = "中文通用"
        case chineseCoding = "中文编程"
        case englishGeneral = "English General"

        var icon: String {
            switch self {
            case .chineseGeneral: return "text.bubble"
            case .chineseCoding: return "chevron.left.forwardslash.chevron.right"
            case .englishGeneral: return "globe.americas"
            }
        }

        var description: String {
            switch self {
            case .chineseGeneral: return "语音记录想法、会议、待办"
            case .chineseCoding: return "语音描述编程任务和代码修改"
            case .englishGeneral: return "Voice notes, ideas, meetings"
            }
        }

        var sttEngine: STTEngine { .apple }

        var sttLanguage: String {
            switch self {
            case .chineseGeneral, .chineseCoding: return "zh-CN"
            case .englishGeneral: return "en-US"
            }
        }

        var promptTemplate: PromptTemplate {
            .smartAutoDetect
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text("B-talk 快速配置")
                    .font(.system(size: 18, weight: .semibold))
                Text("选择你的常用场景，一键配好所有设置")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            switch step {
            case .choosePreset:
                presetSelectionView
            case .apiKeys:
                apiKeyEntryView
            case .done:
                doneView
            }
        }
        .frame(width: 460, height: 420)
    }

    // MARK: - Preset Selection

    private var presetSelectionView: some View {
        VStack(spacing: 16) {
            ForEach(SetupPreset.allCases, id: \.rawValue) { preset in
                presetCard(preset)
            }

            Spacer()

            HStack {
                Button("跳过") {
                    markComplete()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("下一步") {
                    if let preset = selectedPreset {
                        applyPreset(preset)
                        step = .apiKeys
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPreset == nil)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }

    private func presetCard(_ preset: SetupPreset) -> some View {
        Button {
            selectedPreset = preset
        } label: {
            HStack(spacing: 14) {
                Image(systemName: preset.icon)
                    .font(.system(size: 20))
                    .frame(width: 36)
                    .foregroundStyle(selectedPreset == preset ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(preset.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedPreset == preset {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedPreset == preset
                          ? Color.blue.opacity(0.08)
                          : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selectedPreset == preset
                                  ? Color.blue.opacity(0.3)
                                  : Color.clear,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    // MARK: - API Key Entry

    @State private var llmKeyInput: String = ""
    @State private var llmKeyRevealed = false
    @State private var keySaved = false

    private var apiKeyEntryView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("配置 LLM API Key")
                    .font(.system(size: 14, weight: .semibold))

                Text("语音转写使用 Apple 系统 STT（无需 API Key）。\nLLM 用于将转写文本整理为结构化内容。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                HStack {
                    Text("Provider")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $settings.llmProvider) {
                        ForEach(LLMProviderType.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .frame(width: 200)
                }

                HStack(spacing: 6) {
                    if llmKeyRevealed {
                        TextField("API Key", text: $llmKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("API Key", text: $llmKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    Button {
                        llmKeyRevealed.toggle()
                    } label: {
                        Image(systemName: llmKeyRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Button("Save") {
                        saveLLMKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(llmKeyInput.isEmpty)
                }

                if keySaved {
                    Text("Key 已保存")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("上一步") {
                    step = .choosePreset
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button(keySaved ? "完成" : "稍后配置") {
                    markComplete()
                    step = .done
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("配置完成！")
                .font(.system(size: 16, weight: .semibold))

            let s = AppSettings.shared
            let hk = hotKeyDisplayString(
                keyCode: s.hotKeyCode,
                modifiers: s.hotKeyModifiers,
                rightCommandOnly: s.hotKeyRightCommandOnly
            )

            VStack(spacing: 6) {
                Text("按 \(hk) 开始/停止录音")
                    .font(.system(size: 13))
                Text("结果出现后按 \(hk) 粘贴整理文本")
                    .font(.system(size: 13))
                Text("按 Esc 粘贴原始文本")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("开始使用") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func applyPreset(_ preset: SetupPreset) {
        settings.sttEngine = preset.sttEngine
        settings.appleLanguage = preset.sttLanguage
        settings.promptTemplate = preset.promptTemplate
    }

    private func saveLLMKey() {
        let keychainKey: String
        switch settings.llmProvider {
        case .claude: keychainKey = KeychainManager.claudeKey
        case .openAI, .custom: keychainKey = KeychainManager.openAILLMKey
        case .gemini: keychainKey = KeychainManager.geminiKey
        }
        KeychainManager.save(key: keychainKey, value: llmKeyInput)
        keySaved = true
    }

    private func markComplete() {
        UserDefaults.standard.set(true, forKey: "quickSetup.completed")
    }
}
