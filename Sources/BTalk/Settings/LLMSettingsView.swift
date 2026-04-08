import SwiftUI

// MARK: - Static model lists (shown before "Fetch Models" is used)
private let claudeDefaultModels = [
    "claude-opus-4-6",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
]
private let openAIDefaultModels = [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-3.5-turbo",
]
private let geminiDefaultModels = [
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
    "gemini-1.5-pro",
    "gemini-1.5-flash",
]

struct LLMSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var claudeKeyInput = ""
    @State private var openAIKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var testStatus: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $settings.llmProvider) {
                    ForEach(LLMProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.llmProvider) { _ in
                    availableModels = []
                    testStatus = nil
                }
            }

            switch settings.llmProvider {
            case .claude:  claudeSection
            case .openAI:  openAISection
            case .gemini:  geminiSection
            case .custom:  customSection
            }

            Section("Parameters") {
                LabeledContent("Temperature: \(String(format: "%.1f", settings.temperature))") {
                    Slider(value: $settings.temperature, in: 0...1, step: 0.1)
                        .frame(maxWidth: 200)
                }
                LabeledContent("Max Tokens: \(settings.maxTokens)") {
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxTokens) },
                            set: { settings.maxTokens = Int($0) }
                        ),
                        in: 256...4096, step: 256
                    )
                    .frame(maxWidth: 200)
                }
            }

            Section {
                HStack {
                    Button("Test Connection") { testConnection() }
                        .disabled(isTesting || currentKey.isEmpty)

                    if settings.llmProvider != .custom {
                        Button("Fetch Models") { fetchModels() }
                            .disabled(isFetchingModels || currentKey.isEmpty)
                    }

                    if isTesting || isFetchingModels {
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

    // MARK: - Provider Sections

    @ViewBuilder
    private var claudeSection: some View {
        Section("Claude (Anthropic) Configuration") {
            APIKeyField(label: "API Key", value: $claudeKeyInput) {
                KeychainManager.save(key: KeychainManager.claudeKey, value: claudeKeyInput)
            }
            LabeledContent("Base URL") {
                TextField("https://api.anthropic.com", text: $settings.claudeBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            modelPicker(for: $settings.claudeModel, defaults: claudeDefaultModels)
        }
    }

    @ViewBuilder
    private var openAISection: some View {
        Section("OpenAI GPT Configuration") {
            APIKeyField(label: "API Key", value: $openAIKeyInput) {
                KeychainManager.save(key: KeychainManager.openAILLMKey, value: openAIKeyInput)
            }
            LabeledContent("Base URL") {
                TextField("https://api.openai.com", text: $settings.openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            modelPicker(for: $settings.openAILLMModel, defaults: openAIDefaultModels)
        }
    }

    @ViewBuilder
    private var geminiSection: some View {
        Section("Google Gemini Configuration") {
            APIKeyField(label: "API Key", value: $geminiKeyInput) {
                KeychainManager.save(key: KeychainManager.geminiKey, value: geminiKeyInput)
            }
            modelPicker(for: $settings.geminiModel, defaults: geminiDefaultModels)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        Section("Custom OpenAI-compatible Endpoint") {
            APIKeyField(label: "API Key", value: $openAIKeyInput) {
                KeychainManager.save(key: KeychainManager.openAILLMKey, value: openAIKeyInput)
            }
            LabeledContent("Base URL") {
                TextField("https://your-proxy.com", text: $settings.customBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Model ID") {
                TextField("Enter model ID manually", text: $settings.customModel)
                    .textFieldStyle(.roundedBorder)
            }
            Label("Custom endpoints: enter model ID manually.", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Model Picker (always a dropdown)

    @ViewBuilder
    private func modelPicker(for binding: Binding<String>, defaults: [String]) -> some View {
        let models = availableModels.isEmpty ? defaults : availableModels
        let allModels = models.contains(binding.wrappedValue)
            ? models
            : models + [binding.wrappedValue]

        Picker("Model", selection: binding) {
            ForEach(allModels, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Helpers

    private var currentKey: String {
        switch settings.llmProvider {
        case .claude:          return claudeKeyInput
        case .openAI, .custom: return openAIKeyInput
        case .gemini:          return geminiKeyInput
        }
    }

    private func loadKeys() {
        claudeKeyInput = KeychainManager.load(key: KeychainManager.claudeKey) ?? ""
        openAIKeyInput = KeychainManager.load(key: KeychainManager.openAILLMKey) ?? ""
        geminiKeyInput = KeychainManager.load(key: KeychainManager.geminiKey) ?? ""
    }

    private func testConnection() {
        isTesting = true
        testStatus = nil
        Task {
            do {
                switch settings.llmProvider {
                case .claude:
                    let models = try await ClaudeProvider.fetchModels(
                        apiKey: claudeKeyInput, baseURL: settings.claudeBaseURL)
                    testStatus = "✓ Connected (\(models.count) models)"
                    availableModels = models
                case .openAI, .custom:
                    let baseURL = settings.llmProvider == .custom
                        ? settings.customBaseURL : settings.openAIBaseURL
                    let models = try await OpenAIProvider.fetchModels(
                        apiKey: openAIKeyInput, baseURL: baseURL)
                    testStatus = "✓ Connected (\(models.count) models)"
                    availableModels = models
                case .gemini:
                    let models = try await GeminiProvider.fetchModels(apiKey: geminiKeyInput)
                    testStatus = "✓ Connected (\(models.count) models)"
                    availableModels = models
                }
            } catch {
                testStatus = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        Task {
            do {
                switch settings.llmProvider {
                case .claude:
                    availableModels = try await ClaudeProvider.fetchModels(
                        apiKey: claudeKeyInput, baseURL: settings.claudeBaseURL)
                case .openAI, .custom:
                    let baseURL = settings.llmProvider == .custom
                        ? settings.customBaseURL : settings.openAIBaseURL
                    availableModels = try await OpenAIProvider.fetchModels(
                        apiKey: openAIKeyInput, baseURL: baseURL)
                case .gemini:
                    availableModels = try await GeminiProvider.fetchModels(apiKey: geminiKeyInput)
                }
            } catch {
                testStatus = "✗ Failed to fetch models"
            }
            isFetchingModels = false
        }
    }
}
