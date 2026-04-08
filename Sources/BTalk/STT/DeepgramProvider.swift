import Foundation

/// Deepgram Nova-3 streaming STT via WebSocket.
/// For Chinese use AzureSpeechProvider instead - Deepgram nova-3 multi does NOT support Mandarin.
/// Best for English or Deepgram's supported multilingual combinations.
/// Docs: https://developers.deepgram.com/docs/live-streaming-audio
final class DeepgramProvider: STTProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let language: String

    private let wsClient = WebSocketClient()
    private var transcriptContinuation: AsyncStream<STTResult>.Continuation?
    private var finalTranscriptParts: [String] = []
    private var stopContinuation: CheckedContinuation<String, Error>?
    private var keepAliveTask: Task<Void, Never>?

    /// - Parameters:
    ///   - model: "nova-3" recommended. Flux for ultra-low-latency English-only.
    ///   - language: "en" for English, "multi" for multilingual (no Mandarin).
    init(apiKey: String, model: String = "nova-3", language: String = "en") {
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    func startStreaming(language: String) async throws -> AsyncStream<STTResult> {
        let lang = language.isEmpty ? self.language : language
        finalTranscriptParts = []

        // Deepgram streaming endpoint
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: lang),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "100"),  // Recommended for multilingual
        ]

        guard let url = components.url else {
            throw STTError.invalidConfiguration("Invalid Deepgram URL")
        }

        let headers = ["Authorization": "Token \(apiKey)"]

        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            self.transcriptContinuation = continuation

            Task {
                await self.wsClient.connect(
                    to: url,
                    headers: headers,
                    onMessage: { [weak self] result in
                        self?.handleDeepgramMessage(result: result)
                    },
                    onDisconnect: { [weak self] _ in
                        self?.transcriptContinuation?.finish()
                        self?.keepAliveTask?.cancel()
                    }
                )

                // Start KeepAlive to prevent silent-period disconnection
                self.startKeepAlive()
            }
        }
    }

    func sendAudioData(_ data: Data) async throws {
        try await wsClient.send(data: data)
    }

    func stopStreaming() async throws -> String {
        keepAliveTask?.cancel()
        keepAliveTask = nil

        // Send Finalize to signal end of audio stream
        try? await wsClient.send(text: "{\"type\": \"Finalize\"}")
        // Wait for remaining final results from Deepgram
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await wsClient.disconnect()
        transcriptContinuation?.finish()
        return finalTranscriptParts.joined(separator: " ")
    }

    private func startKeepAlive() {
        keepAliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Every 5 seconds
                guard !Task.isCancelled else { break }
                try? await wsClient.send(text: "{\"type\": \"KeepAlive\"}")
            }
        }
    }

    private func handleDeepgramMessage(result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let msg):
            if case .string(let text) = msg {
                parseDeepgramResponse(text)
            }
        case .failure(let error):
            stopContinuation?.resume(throwing: error)
            stopContinuation = nil
        }
    }

    private func parseDeepgramResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let msgType = json["type"] as? String else { return }

        if msgType == "Results" {
            guard let channel = (json["channel"] as? [String: Any]),
                  let alternatives = channel["alternatives"] as? [[String: Any]],
                  let first = alternatives.first,
                  let transcript = first["transcript"] as? String,
                  !transcript.isEmpty else { return }

            let isFinal = json["is_final"] as? Bool ?? false
            let confidence = first["confidence"] as? Float ?? 0.8

            if isFinal {
                finalTranscriptParts.append(transcript)
            }

            transcriptContinuation?.yield(STTResult(
                text: transcript,
                isFinal: isFinal,
                confidence: confidence
            ))
        } else if msgType == "Finalized" {
            // All final results received
            let transcript = finalTranscriptParts.joined(separator: " ")
            stopContinuation?.resume(returning: transcript)
            stopContinuation = nil
            transcriptContinuation?.finish()
        } else if msgType == "Error" {
            let msg = json["message"] as? String ?? "Unknown Deepgram error"
            stopContinuation?.resume(throwing: STTError.transcriptionFailed(msg))
            stopContinuation = nil
        }
    }
}
