import Foundation

/// Google Gemini LLM provider using SSE streaming.
/// Uses streamGenerateContent with alt=sse for server-sent events.
final class GeminiProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let template: PromptTemplate
    private let temperature: Double
    private let maxTokens: Int

    private static let baseURL = "https://generativelanguage.googleapis.com"

    init(
        apiKey: String,
        model: String = "gemini-2.0-flash",
        template: PromptTemplate = .smartAutoDetect,
        temperature: Double = 0.3,
        maxTokens: Int = 1024
    ) {
        self.apiKey = apiKey
        self.model = model
        self.template = template
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func structure(transcript: String) async throws -> String {
        return try await structureStreaming(transcript: transcript, onChunk: { _ in })
    }

    func structureStreaming(
        transcript: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw LLMError.invalidConfiguration("Invalid Gemini URL")
        }

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": template.systemPrompt]]
            ],
            "contents": [
                ["role": "user", "parts": [["text": transcript]]]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxTokens
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var fullText = ""

        let stream = SSEClient.stream(url: url, headers: [:], body: bodyData)
        for try await event in stream {
            if let chunk = parseChunk(event.data) {
                fullText += chunk
                onChunk(chunk)
            }
        }

        return fullText
    }

    private func parseChunk(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { return nil }
        return text
    }

    static func fetchModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/v1beta/models?key=\(apiKey)") else {
            throw LLMError.invalidConfiguration("Invalid URL")
        }

        let data = try await HTTPClient.get(url: url, headers: [:])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }

        return models
            .compactMap { $0["name"] as? String }
            .compactMap { name -> String? in
                // "models/gemini-2.0-flash" → "gemini-2.0-flash"
                guard name.hasPrefix("models/") else { return nil }
                return String(name.dropFirst("models/".count))
            }
            .filter { $0.hasPrefix("gemini") }
            .sorted()
    }
}
