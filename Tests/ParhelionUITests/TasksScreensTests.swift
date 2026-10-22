import Foundation
import Testing

@testable import ParhelionUI

// A copy of the views of Examples/Tasks, whose screens show most of the
// system interface Parhelion draws: a large title, a toolbar button, a list,
// a back button, an alert, and a sheet with a toolbar. The README shows them.
// A test checks that the copy matches the example, apart from `private`.

private struct TaskItem: Identifiable, Codable {
    var id: Int
    var title: String
    var isDone = false
}

private struct TaskListView: View {
    @State private var tasks = [
        TaskItem(id: 1, title: "Buy milk"),
        TaskItem(id: 2, title: "Call the dentist"),
        TaskItem(id: 3, title: "Water the plants", isDone: true),
    ]
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section("To do") {
                    ForEach(tasks.filter { !$0.isDone }) { task in
                        NavigationLink(task.title, value: task.id)
                    }
                }
                Section {
                    ForEach(tasks.filter(\.isDone)) { task in
                        NavigationLink(value: task.id) {
                            Text(task.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Done")
                } footer: {
                    Text("Open a task to mark it done or delete it.")
                }
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: Int.self) { id in
                TaskDetailView(task: binding(for: id)) {
                    tasks.removeAll { $0.id == id }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                NewTaskView { title in
                    let id = (tasks.map(\.id).max() ?? 0) + 1
                    withAnimation {
                        tasks.append(TaskItem(id: id, title: title))
                    }
                }
            }
        }
    }

    private func binding(for id: Int) -> Binding<TaskItem> {
        Binding(
            get: { tasks.first { $0.id == id } ?? TaskItem(id: id, title: "Deleted") },
            set: { task in
                if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index] = task }
            }
        )
    }
}

private struct TaskDetailView: View {
    @Binding var task: TaskItem
    var onDelete: () -> Void
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(task.isDone ? "Done" : "Not done yet")
            Button(task.isDone ? "Mark as not done" : "Mark as done") {
                withAnimation { task.isDone.toggle() }
            }
            Button("Delete", role: .destructive) {
                isConfirmingDelete = true
            }
        }
        .navigationTitle(task.title)
        .alert("Delete this task?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You cannot undo this.")
        }
    }
}

private struct NewTaskView: View {
    var onAdd: (String) -> Void
    @State private var title = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Title", text: $title)
                    .padding(10)
                    .background(.gray.opacity(0.15))
                Spacer()
            }
            .padding()
            .navigationTitle("New task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(title.isEmpty ? "Untitled" : title)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The Tasks example's screens, settled after each step.
@MainActor
enum TasksScreens {
    enum Screen: String, CaseIterable {
        case list, detail, alert, sheet
    }

    static func host(showing screen: Screen, device: Device = .iPhone16) throws -> ViewHost {
        let host = ViewHost(TaskListView(), device: device)
        switch screen {
        case .list:
            break
        case .detail:
            try host.tapButton(labeled: "Buy milk")
        case .alert:
            try host.tapButton(labeled: "Buy milk")
            host.advanceTime(by: 2)
            try host.tapButton(labeled: "Delete")
        case .sheet:
            try host.tapButton(labeled: "Add")
        }
        host.advanceTime(by: 2)
        return host
    }

    /// A screen as the README shows it: at 2× with the status bar and the
    /// home indicator, as `--png` draws.
    static func readmeImage(_ screen: Screen) throws -> Data {
        try host(showing: screen).render(scale: 2, chrome: .systemBars).pngData()
    }

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func readmeImageURL(_ screen: Screen, in directory: URL? = nil) -> URL {
        (directory ?? repository.appendingPathComponent("docs/images"))
            .appendingPathComponent("tasks-\(screen.rawValue).png")
    }
}

@MainActor
@Suite("Tasks screens")
struct TasksScreensTests {
    @Test("The test's copy of the Tasks example matches the example")
    func copyMatchesExample() throws {
        let example = try String(
            contentsOf: TasksScreens.repository.appendingPathComponent(
                "Examples/Tasks/TasksApp.swift"),
            encoding: .utf8)
        let copy = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let views = example[example.range(of: "struct TaskItem")!.lowerBound...]
        let copied = copy[
            copy.range(of: "private struct TaskItem")!
                .lowerBound..<copy.range(of: "/// The Tasks example's screens")!.lowerBound
        ]
        #expect(
            copied.replacingOccurrences(of: "private struct", with: "struct")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == views.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Rendering is deterministic, so the README's images must match a fresh
    /// render. After an intended rendering change, regenerate them with
    /// `PARHELION_README_IMAGES=docs/images swift test --filter writeReadmeImages`.
    @Test("The README's Tasks images match a fresh render", arguments: TasksScreens.Screen.allCases)
    func readmeImages(_ screen: TasksScreens.Screen) throws {
        let committed = try Data(contentsOf: TasksScreens.readmeImageURL(screen))
        #expect(try TasksScreens.readmeImage(screen) == committed)
    }

    @Test(
        "Write the README's Tasks images",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] != nil)
    )
    func writeReadmeImages() throws {
        let path = ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] ?? ""
        let directory = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for screen in TasksScreens.Screen.allCases {
            try TasksScreens.readmeImage(screen).write(
                to: TasksScreens.readmeImageURL(screen, in: directory))
        }
    }

    /// Writes the screens at 3× on an iPhone 16 Pro, the size of Apple's iOS
    /// 27 UI Kit, to compare with its artwork. Set `PARHELION_DEMO_DIR` to a
    /// directory, and optionally `PARHELION_DEMO_PREFIX`.
    @Test(
        "Write the Tasks screens at 3×",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] != nil)
    )
    func renderScreens() throws {
        let directory = ProcessInfo.processInfo.environment["PARHELION_DEMO_DIR"] ?? ""
        let prefix = ProcessInfo.processInfo.environment["PARHELION_DEMO_PREFIX"] ?? "tasks-"
        for screen in TasksScreens.Screen.allCases {
            let host = try TasksScreens.host(showing: screen, device: .iPhone16Pro)
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("\(prefix)\(screen.rawValue).png")
            try host.render(scale: 3, chrome: .systemBars).pngData().write(to: url)
        }
    }
}
