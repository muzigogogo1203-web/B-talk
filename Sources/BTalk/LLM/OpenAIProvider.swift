import Foundation

/// OpenAI GPT LLM provider using SSE streaming.
final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let template: PromptTemplate
    private let temperature: Double
    private let maxTokens: Int

    init(
        apiKey: String,
        model: String = "gpt-4o",
        baseURL: String = "https://api.openai.com",
        template: PromptTemplate = .smartAutoDetect,
        temperature: Double = 0.3,
        maxTokens: Int = 1024
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
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
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.invalidConfiguration("Invalid base URL")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
            "messages": [
                ["role": "system", "content": template.systemPrompt],
                ["role": "user", "content": transcript]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let headers = [
            "Authorization": "Bearer \(apiKey)"
        ]

        var fullText = ""
        let stream = SSEClient.stream(url: url, headers: headers, body: bodyData)

        for try await event in stream {
            guard event.data != "[DONE]" else { break }

            if let chunk = parseOpenAIChunk(event.data) {
                fullText += chunk
                onChunk(chunk)
            }
        }

        return fullText
    }

    private func parseOpenAIChunk(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    static func fetchModels(apiKey: String, baseURL: String = "https://api.openai.com") async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw LLMError.invalidConfiguration("Invalid URL")
        }

        let data = try await HTTPClient.get(url: url, headers: [
            "Authorization": "Bearer \(apiKey)"
        ])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["id"] as? String }.sorted()
    }
}
