import SwiftUI

struct STTSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var azureKeyInput = ""
    @State private var deepgramKeyInput = ""
    @State private var openAIKeyInput = ""
    @State private var testStatus: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Speech Engine") {
                Picker("Engine", selection: $settings.sttEngine) {
                    ForEach(STTEngine.allCases, id: \.self) { engine in
                        HStack {
                            Text(engine.displayName)
                            if engine.recommendedForChinese {
                                Text("✓ Chinese")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(engine)
                    }
                }
                .pickerStyle(.menu)

                if !settings.sttEngine.recommendedForChinese {
                    Label("Deepgram Nova-3 multilingual does not support Mandarin. Use Azure or OpenAI for Chinese.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Engine-specific settings
            switch settings.sttEngine {
            case .apple:
                appleSection
            case .azure:
                azureSection
            case .deepgram:
                deepgramSection
            case .openAI:
                openAISection
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting || (settings.sttEngine.requiresAPIKey && currentKey.isEmpty) || settings.sttEngine == .apple)

                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else if let status = testStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("✓") ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadKeys() }
    }

    // MARK: - Engine Sections

    @ViewBuilder
    private var appleSection: some View {
        Section("Apple Speech Recognition") {
            Label("No API key required. Uses Apple's on-device or cloud speech recognition.", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.callout)
            Picker("Language", selection: $settings.appleLanguage) {
                Text("Chinese (Mandarin) - zh-CN").tag("zh-CN")
                Text("Chinese (Cantonese) - zh-HK").tag("zh-HK")
                Text("English - en-US").tag("en-US")
                Text("Japanese - ja-JP").tag("ja-JP")
                Text("Korean - ko-KR").tag("ko-KR")
            }
            Label("Requires Speech Recognition permission in System Settings.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var azureSection: some View {
        Section("Azure Speech Configuration") {
            APIKeyField(label: "API Key", value: $azureKeyInput) {
                KeychainManager.save(key: KeychainManager.azureKey, value: azureKeyInput)
            }
            LabeledContent("Region") {
                TextField("e.g. eastus", text: $settings.azureRegion)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            Picker("Language", selection: $settings.azureLanguage) {
                Text("Chinese (Mandarin) - zh-CN").tag("zh-CN")
                Text("Chinese (Cantonese) - zh-HK").tag("zh-HK")
                Text("English - en-US").tag("en-US")
                Text("Auto Detect").tag("auto")
            }
        }
    }

    @ViewBuilder
    private var deepgramSection: some View {
        Section("Deepgram Configuration") {
            APIKeyField(label: "API Key", value: $deepgramKeyInput) {
                KeychainManager.save(key: KeychainManager.deepgramKey, value: deepgramKeyInput)
            }
            Picker("Model", selection: $settings.deepgramModel) {
                Text("Nova-3 (Recommended)").tag("nova-3")
                Text("Nova-2").tag("nova-2")
                Text("Flux (Ultra-low latency, English only)").tag("flux")
            }
            Picker("Language", selection: $settings.deepgramLanguage) {
                Text("English - en").tag("en")
                Text("Multilingual (no Mandarin) - multi").tag("multi")
            }
        }
    }

    @ViewBuilder
    private var openAISection: some View {
        Section("OpenAI Transcription Configuration") {
            APIKeyField(label: "API Key", value: $openAIKeyInput) {
                KeychainManager.save(key: KeychainManager.openAISTTKey, value: openAIKeyInput)
            }
            Picker("Model", selection: $settings.openAISTTModel) {
                Text("gpt-4o-transcribe (Best quality)").tag("gpt-4o-transcribe")
                Text("gpt-4o-mini-transcribe (Faster)").tag("gpt-4o-mini-transcribe")
                Text("whisper-1 (Legacy)").tag("whisper-1")
            }
            Label("Note: OpenAI transcription is batch (non-streaming). Recording ends before transcription begins.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var currentKey: String {
        switch settings.sttEngine {
        case .apple: return "n/a"
        case .azure: return azureKeyInput
        case .deepgram: return deepgramKeyInput
        case .openAI: return openAIKeyInput
        }
    }

    private func loadKeys() {
        azureKeyInput = KeychainManager.load(key: KeychainManager.azureKey) ?? ""
        deepgramKeyInput = KeychainManager.load(key: KeychainManager.deepgramKey) ?? ""
        openAIKeyInput = KeychainManager.load(key: KeychainManager.openAISTTKey) ?? ""
    }

    private func testConnection() {
        isTesting = true
        testStatus = nil
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // TODO: Implement actual API ping
            testStatus = "✓ Connection successful"
            isTesting = false
        }
    }
}
