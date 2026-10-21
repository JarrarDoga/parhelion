import SwiftUI

@main
struct TasksApp: App {
    var body: some Scene {
        WindowGroup {
            TaskListView()
        }
    }
}

struct TaskItem: Identifiable, Codable {
    var id: Int
    var title: String
    var isDone = false
}

struct TaskListView: View {
    @State private var tasks = [
        TaskItem(id: 1, title: "Buy milk"),
        TaskItem(id: 2, title: "Call the dentist"),
        TaskItem(id: 3, title: "Water the plants", isDone: true),
    ]

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
                    Text("Open a task to mark it done or not done.")
                }
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: Int.self) { id in
                TaskDetailView(task: binding(for: id))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        tasks.append(
                            TaskItem(id: tasks.count + 1, title: "Task \(tasks.count + 1)"))
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

struct TaskDetailView: View {
    @Binding var task: TaskItem

    var body: some View {
        VStack(spacing: 24) {
            Text(task.isDone ? "Done" : "Not done yet")
            Button(task.isDone ? "Mark as not done" : "Mark as done") {
                task.isDone.toggle()
            }
        }
        .navigationTitle(task.title)
    }
}
