import Foundation

/// Claude API LLM provider using SSE streaming.
/// Request: POST with Content-Type: application/json, "stream": true
/// Response: text/event-stream with event: + data: SSE frames
final class ClaudeProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let template: PromptTemplate
    private let temperature: Double
    private let maxTokens: Int

    init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        baseURL: String = "https://api.anthropic.com",
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
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidConfiguration("Invalid base URL")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true,
            "system": template.systemPrompt,
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01"
        ]

        var fullText = ""

        let stream = SSEClient.stream(url: url, headers: headers, body: bodyData)

        for try await event in stream {
            // Handle different SSE event types from Anthropic
            switch event.event {
            case "content_block_delta":
                if let delta = parseDelta(from: event.data) {
                    fullText += delta
                    onChunk(delta)
                }
            case "message_stop":
                break
            case "error":
                if let errorMsg = parseError(from: event.data) {
                    throw LLMError.apiError(errorMsg)
                }
            case "ping", "message_start", "content_block_start", "content_block_stop", "message_delta":
                break // Ignore
            default:
                // Try to parse as content delta for compatibility
                if let delta = parseDelta(from: event.data) {
                    fullText += delta
                    onChunk(delta)
                }
            }
        }

        return fullText
    }

    // MARK: - Parsing helpers

    private func parseDelta(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delta = json["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else {
            return nil
        }
        return text
    }

    private func parseError(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    // MARK: - Fetch available models

    static func fetchModels(apiKey: String, baseURL: String = "https://api.anthropic.com") async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw LLMError.invalidConfiguration("Invalid URL")
        }

        let data = try await HTTPClient.get(url: url, headers: [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01"
        ])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["id"] as? String }.sorted()
    }
}

enum LLMError: Error, LocalizedError {
    case invalidConfiguration(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "LLM config error: \(msg)"
        case .apiError(let msg): return "LLM API error: \(msg)"
        }
    }
}
