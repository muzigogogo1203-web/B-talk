import Foundation

/// A saved voice input item stored in the inspiration library.
struct InspirationItem: Codable, Identifiable {
    var id: UUID
    var rawTranscript: String
    var structuredContent: String
    var createdAt: Date
    var isFavorite: Bool
    var sourceApp: String?
    var tags: [String]

    init(
        rawTranscript: String,
        structuredContent: String,
        sourceApp: String? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.rawTranscript = rawTranscript
        self.structuredContent = structuredContent
        self.createdAt = Date()
        self.isFavorite = false
        self.sourceApp = sourceApp
        self.tags = tags
    }
}
