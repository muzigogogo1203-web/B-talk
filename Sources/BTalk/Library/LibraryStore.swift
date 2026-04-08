import Foundation

/// Simple JSON-file backed store for InspirationItems.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [InspirationItem] = []

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    private init() {
        load()
    }

    func add(_ item: InspirationItem) {
        items.insert(item, at: 0)
        save()
    }

    func delete(_ item: InspirationItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func toggleFavorite(_ item: InspirationItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isFavorite.toggle()
            save()
        }
    }

    func deleteAll() {
        items.removeAll()
        save()
    }

    func filtered(by query: String) -> [InspirationItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.structuredContent.localizedCaseInsensitiveContains(query)
            || $0.rawTranscript.localizedCaseInsensitiveContains(query)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([InspirationItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
