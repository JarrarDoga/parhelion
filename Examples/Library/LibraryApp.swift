import SwiftUI

@main
struct LibraryApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            ShelfView()
                .environment(library)
        }
    }
}

struct Book: Identifiable, Codable {
    var id: Int
    var title: String
    var author: String
    var notes = ""
    var isFavorite = false
}

/// The app's model. It is `Codable`, so `parhelion run` keeps it when the app
/// is rebuilt.
@Observable
final class Library: Codable {
    var name = "Library"
    var books: [Book] = []

    var favoriteCount: Int { books.filter(\.isFavorite).count }

    init() {}

    /// Loads the books, the way an app would fetch them from a server.
    @MainActor
    func load() async {
        guard books.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return  // Cancelled: the shelf left the screen.
        }
        books = [
            Book(id: 1, title: "The Left Hand of Darkness", author: "Ursula K. Le Guin"),
            Book(id: 2, title: "Kindred", author: "Octavia E. Butler"),
            Book(id: 3, title: "Piranesi", author: "Susanna Clarke", isFavorite: true),
        ]
    }

    // @Observable stores each property as `_name`; these keys keep the
    // saved JSON plain.
    enum CodingKeys: String, CodingKey {
        case _name = "name"
        case _books = "books"
    }
}

struct ShelfView: View {
    @Environment(Library.self) private var library
    @State private var isRenaming = false

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        Section {
                            ForEach($library.books) { $book in
                                NavigationLink {
                                    BookView(book: $book)
                                } label: {
                                    BookRow(book: book)
                                }
                            }
                        } footer: {
                            Text("Favorites: \(library.favoriteCount)")
                        }
                    }
                }
            }
            .navigationTitle(library.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rename") { isRenaming = true }
                }
            }
            .sheet(isPresented: $isRenaming) {
                RenameView(library: library)
            }
            .task {
                await library.load()
            }
        }
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.isFavorite ? "★ \(book.title)" : book.title)
            Text(book.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct BookView: View {
    @Binding var book: Book

    var body: some View {
        List {
            Section("Title") {
                TextField("Title", text: $book.title)
            }
            Section("Notes") {
                TextField("Notes", text: $book.notes)
            }
            Section {
                Button(book.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                    book.isFavorite.toggle()
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RenameView: View {
    @Bindable var library: Library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                TextField("Name", text: $library.name)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
