import Foundation

struct STTResult: Sendable {
    let text: String
    let isFinal: Bool
    let confidence: Float
}

protocol STTProvider: Sendable {
    func startStreaming(language: String) async throws -> AsyncStream<STTResult>
    func sendAudioData(_ data: Data) async throws
    /// Sends Finalize/CloseStream, reads remaining results, returns final transcript
    func stopStreaming() async throws -> String
}
