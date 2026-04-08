import SwiftUI

struct LibraryView: View {
    @StateObject private var store = LibraryStore.shared
    @State private var searchText = ""
    @State private var selectedID: UUID?

    var selectedItem: InspirationItem? {
        store.items.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            List(store.filtered(by: searchText), id: \.id, selection: $selectedID) { item in
                LibraryRowView(item: item)
            }
            .searchable(text: $searchText, prompt: "Search...")
            .navigationTitle("Library (\(store.items.count))")
            .toolbar {
                ToolbarItem {
                    Button("Clear All", role: .destructive) {
                        store.deleteAll()
                        selectedID = nil
                    }
                    .disabled(store.items.isEmpty)
                }
            }
        } detail: {
            if let item = selectedItem {
                LibraryDetailView(item: item, store: store)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select an item")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}

struct LibraryRowView: View {
    let item: InspirationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.structuredContent)
                .font(.system(size: 13))
                .lineLimit(2)
            HStack {
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if let app = item.sourceApp {
                    Text("· \(app)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LibraryDetailView: View {
    let item: InspirationItem
    let store: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Structured Content")
                        .font(.headline)
                    Text(item.structuredContent)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Group {
                    Text("Raw Transcript")
                        .font(.headline)
                    Text(item.rawTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button(action: { copyToClipboard() }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { store.toggleFavorite(item) }) {
                        Label(
                            item.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: item.isFavorite ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Delete", role: .destructive) {
                        store.delete(item)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Saved \(item.createdAt.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.structuredContent, forType: .string)
    }
}
