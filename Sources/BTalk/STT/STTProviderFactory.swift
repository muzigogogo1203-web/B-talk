import Foundation

enum STTEngine: String, CaseIterable, Codable {
    case apple = "Apple (Built-in)"
    case azure = "Azure Speech"
    case deepgram = "Deepgram"
    case openAI = "OpenAI Transcription"

    var displayName: String { rawValue }

    var requiresAPIKey: Bool {
        switch self {
        case .apple: return false
        default: return true
        }
    }

    var supportsStreaming: Bool {
        switch self {
        case .apple, .azure, .deepgram: return true
        case .openAI: return false
        }
    }

    var recommendedForChinese: Bool {
        switch self {
        case .apple, .azure, .openAI: return true
        case .deepgram: return false
        }
    }
}

struct STTConfiguration: Codable {
    var engine: STTEngine = .apple
    var appleLanguage: String = "zh-CN"
    var azureKey: String = ""
    var azureRegion: String = "eastus"
    var azureLanguage: String = "zh-CN"
    var deepgramKey: String = ""
    var deepgramModel: String = "nova-3"
    var deepgramLanguage: String = "en"
    var openAIKey: String = ""
    var openAIModel: String = "gpt-4o-transcribe"
}

struct STTProviderFactory {
    static func make(from config: STTConfiguration) -> (any STTProvider)? {
        switch config.engine {
        case .apple:
            return AppleSTTProvider(language: config.appleLanguage)
        case .azure:
            guard !config.azureKey.isEmpty else { return nil }
            return AzureSpeechProvider(
                apiKey: config.azureKey,
                region: config.azureRegion,
                language: config.azureLanguage
            )
        case .deepgram:
            guard !config.deepgramKey.isEmpty else { return nil }
            return DeepgramProvider(
                apiKey: config.deepgramKey,
                model: config.deepgramModel,
                language: config.deepgramLanguage
            )
        case .openAI:
            guard !config.openAIKey.isEmpty else { return nil }
            return OpenAITranscriptionProvider(
                apiKey: config.openAIKey,
                model: config.openAIModel
            )
        }
    }
}
