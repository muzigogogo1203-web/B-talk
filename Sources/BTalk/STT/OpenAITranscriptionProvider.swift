import Foundation

/// OpenAI Transcription API - batch mode (non-streaming).
/// Supports gpt-4o-transcribe and gpt-4o-mini-transcribe.
/// Excellent multilingual support including Mandarin Chinese.
final class OpenAITranscriptionProvider: STTProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String // "gpt-4o-transcribe" or "gpt-4o-mini-transcribe"

    private var audioBuffer: Data = Data()
    private var transcriptContinuation: AsyncStream<STTResult>.Continuation?

    init(apiKey: String, model: String = "gpt-4o-transcribe") {
        self.apiKey = apiKey
        self.model = model
    }

    func startStreaming(language: String) async throws -> AsyncStream<STTResult> {
        audioBuffer = Data()
        return AsyncStream { [weak self] continuation in
            self?.transcriptContinuation = continuation
        }
    }

    func sendAudioData(_ data: Data) async throws {
        audioBuffer.append(data)
    }

    func stopStreaming() async throws -> String {
        transcriptContinuation?.finish()
        transcriptContinuation = nil

        // Build multipart form data with WAV header
        let wavData = addWAVHeader(to: audioBuffer)
        let boundary = "BTalk\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add response_format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw STTError.transcriptionFailed("OpenAI API error")
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Add a minimal WAV header to raw Linear16 PCM data (16kHz, mono)
    private func addWAVHeader(to pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: chunkSize.littleEndianBytes)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: UInt32(16).littleEndianBytes)
        header.append(contentsOf: UInt16(1).littleEndianBytes)
        header.append(contentsOf: channels.littleEndianBytes)
        header.append(contentsOf: sampleRate.littleEndianBytes)
        header.append(contentsOf: byteRate.littleEndianBytes)
        header.append(contentsOf: blockAlign.littleEndianBytes)
        header.append(contentsOf: bitsPerSample.littleEndianBytes)
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: dataSize.littleEndianBytes)
        header.append(pcmData)

        return header
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        let val = self.littleEndian
        return [UInt8(val & 0xFF), UInt8((val >> 8) & 0xFF),
                UInt8((val >> 16) & 0xFF), UInt8((val >> 24) & 0xFF)]
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        let val = self.littleEndian
        return [UInt8(val & 0xFF), UInt8((val >> 8) & 0xFF)]
    }
}
