import Foundation

/// Azure Cognitive Services Speech-to-Text via WebSocket streaming.
/// Supports zh-CN (Mandarin) with excellent accuracy.
/// Docs: https://learn.microsoft.com/azure/cognitive-services/speech-service/
final class AzureSpeechProvider: STTProvider, @unchecked Sendable {
    private let apiKey: String
    private let region: String
    private let language: String

    private let wsClient = WebSocketClient()
    private var transcriptContinuation: AsyncStream<STTResult>.Continuation?
    private var finalTranscriptParts: [String] = []
    private var stopContinuation: CheckedContinuation<String, Error>?

    init(apiKey: String, region: String = "eastus", language: String = "zh-CN") {
        self.apiKey = apiKey
        self.region = region
        self.language = language
    }

    func startStreaming(language: String) async throws -> AsyncStream<STTResult> {
        let lang = language.isEmpty ? self.language : language
        finalTranscriptParts = []

        // Azure Speech WebSocket endpoint
        let endpoint = "wss://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=\(lang)&format=detailed"
        guard let url = URL(string: endpoint) else {
            throw STTError.invalidConfiguration("Invalid Azure endpoint")
        }

        let headers = [
            "Ocp-Apim-Subscription-Key": apiKey
        ]

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
                        self?.handleAzureMessage(result: result)
                    },
                    onDisconnect: { [weak self] _ in
                        self?.transcriptContinuation?.finish()
                    }
                )
            }
        }
    }

    func sendAudioData(_ data: Data) async throws {
        try await wsClient.send(data: data)
    }

    func stopStreaming() async throws -> String {
        // Wait for final results then close
        try? await Task.sleep(nanoseconds: 500_000_000)
        await wsClient.disconnect()
        transcriptContinuation?.finish()
        let transcript = finalTranscriptParts.joined(separator: " ")
        return transcript
    }

    private func handleAzureMessage(result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let msg):
            if case .string(let text) = msg {
                parseAzureResponse(text)
            }
        case .failure(let error):
            stopContinuation?.resume(throwing: error)
            stopContinuation = nil
        }
    }

    private func parseAzureResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let recognitionStatus = json["RecognitionStatus"] as? String

        if recognitionStatus == "Success" {
            // Get the display text
            if let displayText = json["DisplayText"] as? String, !displayText.isEmpty {
                finalTranscriptParts.append(displayText)
                transcriptContinuation?.yield(STTResult(
                    text: displayText,
                    isFinal: true,
                    confidence: 1.0
                ))
            }
        } else if recognitionStatus == "InitialSilenceTimeout" || recognitionStatus == "BabbleTimeout" {
            // No speech detected
            transcriptContinuation?.finish()
        }

        // Handle interim results (NBest)
        if let nbest = json["NBest"] as? [[String: Any]],
           let best = nbest.first,
           let display = best["Display"] as? String {
            transcriptContinuation?.yield(STTResult(
                text: display,
                isFinal: false,
                confidence: best["Confidence"] as? Float ?? 0.8
            ))
        }
    }
}

enum STTError: Error, LocalizedError {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "Invalid STT configuration: \(msg)"
        case .connectionFailed(let msg): return "STT connection failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        }
    }
}
