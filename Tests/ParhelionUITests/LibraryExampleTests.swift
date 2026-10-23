import Foundation
import Observation
import Testing

@testable import ParhelionUI

// A copy of the models and views of Examples/Library, which use
// @Observable, @Bindable, ForEach($items), and task. A test checks that the
// copy matches the example, apart from `private`.

private struct Book: Identifiable, Codable {
    var id: Int
    var title: String
    var author: String
    var notes = ""
    var isFavorite = false
}

/// The app's model. It is `Codable`, so `parhelion run` keeps it when the app
/// is rebuilt.
@Observable
private final class Library: Codable {
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

private struct ShelfView: View {
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

private struct BookRow: View {
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

private struct BookView: View {
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

private struct RenameView: View {
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

/// The Library example's app, without `@main`.
private struct LibraryTestApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            ShelfView()
                .environment(library)
        }
    }
}

@MainActor
@Suite("Library example")
struct LibraryExampleTests {
    @Test("The test's copy of the Library example matches the example")
    func copyMatchesExample() throws {
        let example = try String(
            contentsOf: TasksScreens.repository.appendingPathComponent(
                "Examples/Library/LibraryApp.swift"),
            encoding: .utf8)
        let copy = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let views = example[example.range(of: "struct Book")!.lowerBound...]
        let copied = copy[
            copy.range(of: "private struct Book")!
                .lowerBound..<copy.range(of: "/// The Library example's app")!.lowerBound
        ]
        #expect(
            copied.replacingOccurrences(of: "private struct", with: "struct")
                .replacingOccurrences(of: "private final class", with: "final class")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == views.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("The shelf shows a placeholder until its task loads the books")
    func loading() async {
        let host = ViewHost(anyRootView: AppRoot(app: LibraryTestApp()))
        #expect(host.pendingTaskCount == 1)
        #expect(host.nodes(withText: "Loading…").count == 1)

        await host.waitForTasks()
        #expect(host.pendingTaskCount == 0)
        #expect(
            host.root.outline() == """
                Root
                └─ NavigationStack
                   ├─ NavigationBar titleDisplayMode=large
                   │  ├─ Text "Library" font=largeTitle.bold
                   │  └─ ToolbarItemGroup placement=trailing
                   │     └─ Button
                   │        └─ Text "Rename" font=body.medium
                   └─ List contentOffset=0, 0 contentSize=393 × 272
                      └─ Section
                         ├─ NavigationLink listRow
                         │  └─ VStack alignment=leading spacing=2
                         │     ├─ Text "The Left Hand of Darkness"
                         │     └─ Text "Ursula K. Le Guin" font=subheadline foregroundStyle=secondary
                         ├─ NavigationLink listRow
                         │  └─ VStack alignment=leading spacing=2
                         │     ├─ Text "Kindred"
                         │     └─ Text "Octavia E. Butler" font=subheadline foregroundStyle=secondary
                         ├─ NavigationLink listRow
                         │  └─ VStack alignment=leading spacing=2
                         │     ├─ Text "★ Piranesi"
                         │     └─ Text "Susanna Clarke" font=subheadline foregroundStyle=secondary
                         └─ SectionFooter
                            └─ Text "Favorites: 1" font=system(13)
                """
        )
    }

    @Test("A book's screen edits the book through a binding from ForEach")
    func editBook() async throws {
        let host = ViewHost(anyRootView: AppRoot(app: LibraryTestApp()))
        await host.waitForTasks()
        try host.tapButton(labeled: "Kindred Octavia E. Butler")
        host.advanceTime(by: 1)

        let title = try #require(
            host.root.allNodes.first {
                $0.kind == "TextField" && $0.attributes["value"] == "Kindred"
            })
        try host.focus(title.id)
        host.typeText(" (1979)")
        try host.tapButton(labeled: "Add to Favorites")
        #expect(host.nodes(withText: "Kindred (1979)").count == 1)
        try host.tapButton(labeled: "Library")
        host.advanceTime(by: 1)

        #expect(host.nodes(withText: "★ Kindred (1979)").count == 1)
        #expect(host.nodes(withText: "Favorites: 2").count == 1)
    }

    @Test("The rename sheet edits the library through @Bindable")
    func rename() async throws {
        let host = ViewHost(anyRootView: AppRoot(app: LibraryTestApp()))
        await host.waitForTasks()
        try host.tapButton(labeled: "Rename")
        host.advanceTime(by: 1)

        let field = try #require(host.interactiveRoot.allNodes.first { $0.kind == "TextField" })
        try host.focus(field.id)
        host.typeText(" of Babel")
        try host.tapButton(labeled: "Done")
        host.advanceTime(by: 1)
        #expect(!host.root.children.contains { $0.isPresentation })
        #expect(host.nodes(withText: "Library of Babel").count == 1)
    }

    @Test("The app's Codable library survives a snapshot and restore without loading again")
    func snapshot() async throws {
        let first = ViewHost(anyRootView: AppRoot(app: LibraryTestApp()))
        await first.waitForTasks()
        try first.tapButton(labeled: "Kindred Octavia E. Butler")
        try first.tapButton(labeled: "Add to Favorites")
        let snapshot = first.stateSnapshot()
        let values = try JSONDecoder().decode([String: String].self, from: snapshot)
        #expect(values["LibraryTestApp._library"]?.contains(#""name":"Library""#) == true)

        let second = ViewHost(anyRootView: AppRoot(app: LibraryTestApp()), restoring: snapshot)
        #expect(second.nodes(withText: "★ Kindred").count == 1)
        #expect(second.nodes(withText: "Favorites: 2").count == 1)
        await second.waitForTasks()
        #expect(second.nodes(withText: "Favorites: 2").count == 1)
    }
}
