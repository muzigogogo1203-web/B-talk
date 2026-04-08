import Foundation
import SwiftUI

enum LLMProviderType: String, CaseIterable, Codable {
    case claude = "Claude (Anthropic)"
    case openAI = "OpenAI GPT"
    case gemini = "Google Gemini"
    case custom = "Custom (OpenAI-compatible)"

    var displayName: String { rawValue }
}

/// Global app settings stored in UserDefaults.
/// API Keys are stored in Keychain, not here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // STT
    @AppStorage("stt.engine") var sttEngine: STTEngine = .apple
    @AppStorage("stt.apple.language") var appleLanguage: String = "zh-CN"
    @AppStorage("stt.azure.region") var azureRegion: String = "eastus"
    @AppStorage("stt.azure.language") var azureLanguage: String = "zh-CN"
    @AppStorage("stt.deepgram.model") var deepgramModel: String = "nova-3"
    @AppStorage("stt.deepgram.language") var deepgramLanguage: String = "en"
    @AppStorage("stt.openai.model") var openAISTTModel: String = "gpt-4o-transcribe"

    // LLM
    @AppStorage("llm.provider") var llmProvider: LLMProviderType = .claude
    @AppStorage("llm.claude.model") var claudeModel: String = "claude-sonnet-4-6"
    @AppStorage("llm.claude.baseURL") var claudeBaseURL: String = "https://api.anthropic.com"
    @AppStorage("llm.openai.model") var openAILLMModel: String = "gpt-4o"
    @AppStorage("llm.openai.baseURL") var openAIBaseURL: String = "https://api.openai.com"
    @AppStorage("llm.gemini.model") var geminiModel: String = "gemini-2.0-flash"
    @AppStorage("llm.custom.baseURL") var customBaseURL: String = ""
    @AppStorage("llm.custom.model") var customModel: String = ""
    @AppStorage("llm.temperature") var temperature: Double = 0.3
    @AppStorage("llm.maxTokens") var maxTokens: Int = 1024
    @AppStorage("llm.promptTemplate") var promptTemplate: PromptTemplate = .smartAutoDetect

    // Hotkey — default: Right Command + Space
    @AppStorage("hotkey.keyCode") var hotKeyCode: Int = 49 // Space
    @AppStorage("hotkey.modifiers") var hotKeyModifiers: Int = 1048576 // Command (.maskCommand)
    @AppStorage("hotkey.rightCommandOnly") var hotKeyRightCommandOnly: Bool = true

    // Raw paste hotkey — default: disabled (0 = not set, use Esc in floating window only)
    @AppStorage("hotkey.rawPaste.keyCode") var rawPasteKeyCode: Int = 0
    @AppStorage("hotkey.rawPaste.modifiers") var rawPasteModifiers: Int = 0
    @AppStorage("hotkey.rawPaste.rightCommandOnly") var rawPasteRightCommandOnly: Bool = false

    // General
    @AppStorage("general.defaultOutput") var defaultOutput: String = "ask" // "paste", "library", "ask"

    // Build STT config for factory
    func buildSTTConfig() -> STTConfiguration {
        var config = STTConfiguration()
        config.engine = sttEngine
        config.appleLanguage = appleLanguage
        config.azureKey = KeychainManager.load(key: KeychainManager.azureKey) ?? ""
        config.azureRegion = azureRegion
        config.azureLanguage = azureLanguage
        config.deepgramKey = KeychainManager.load(key: KeychainManager.deepgramKey) ?? ""
        config.deepgramModel = deepgramModel
        config.deepgramLanguage = deepgramLanguage
        config.openAIKey = KeychainManager.load(key: KeychainManager.openAISTTKey) ?? ""
        config.openAIModel = openAISTTModel
        return config
    }

    // Build LLM provider
    func buildLLMProvider() -> (any LLMProvider)? {
        switch llmProvider {
        case .claude:
            let key = KeychainManager.load(key: KeychainManager.claudeKey) ?? ""
            guard !key.isEmpty else { return nil }
            return ClaudeProvider(
                apiKey: key,
                model: claudeModel,
                baseURL: claudeBaseURL,
                template: promptTemplate,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .openAI:
            let key = KeychainManager.load(key: KeychainManager.openAILLMKey) ?? ""
            guard !key.isEmpty else { return nil }
            return OpenAIProvider(
                apiKey: key,
                model: openAILLMModel,
                baseURL: openAIBaseURL,
                template: promptTemplate,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .gemini:
            let key = KeychainManager.load(key: KeychainManager.geminiKey) ?? ""
            guard !key.isEmpty else { return nil }
            return GeminiProvider(
                apiKey: key,
                model: geminiModel,
                template: promptTemplate,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .custom:
            let key = KeychainManager.load(key: KeychainManager.openAILLMKey) ?? ""
            guard !key.isEmpty, !customBaseURL.isEmpty, !customModel.isEmpty else { return nil }
            return OpenAIProvider(
                apiKey: key,
                model: customModel,
                baseURL: customBaseURL,
                template: promptTemplate,
                temperature: temperature,
                maxTokens: maxTokens
            )
        }
    }
}
