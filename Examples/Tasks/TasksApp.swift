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
        List {
            Section("To do") {
                ForEach(tasks.filter { !$0.isDone }) { task in
                    Button(action: { toggle(task) }) {
                        Text(task.title)
                            .foregroundStyle(.primary)
                    }
                }
            }
            Section {
                ForEach(tasks.filter(\.isDone)) { task in
                    Button(action: { toggle(task) }) {
                        Text(task.title)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Done")
            } footer: {
                Text("Tap a task to move it between lists.")
            }
            Section {
                Button("Add task") {
                    tasks.append(TaskItem(id: tasks.count + 1, title: "Task \(tasks.count + 1)"))
                }
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
    }
}
