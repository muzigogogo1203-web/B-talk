import Foundation

struct StructuredInstruction: Codable, Sendable {
    let context: String
    let action: String
    let detail: String
    let priority: String?
}

struct StructuredOutput: Codable, Sendable {
    let instructions: [StructuredInstruction]
    let summary: String
    let rawTranscript: String

    enum CodingKeys: String, CodingKey {
        case instructions, summary
        case rawTranscript = "raw_transcript"
    }
}

protocol LLMProvider: Sendable {
    /// Structure a raw transcript into coding instructions.
    /// Returns formatted text for display.
    func structure(transcript: String) async throws -> String

    /// Stream structured output, calling onChunk with each text delta.
    func structureStreaming(
        transcript: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
}
