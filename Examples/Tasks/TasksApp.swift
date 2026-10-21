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
                    tasks.append(TaskItem(id: id, title: title))
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
    var onDelete: () -> Void
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(task.isDone ? "Done" : "Not done yet")
            Button(task.isDone ? "Mark as not done" : "Mark as done") {
                task.isDone.toggle()
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

struct NewTaskView: View {
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
