// MARK: - Modifiers

extension View {
    /// Runs `action` when the view appears on screen: after the update that
    /// puts it there, before the next frame.
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        LifecycleView(content: self, handler: action.map { .appear($0) })
    }

    /// Runs `action` when the view leaves the screen: when it leaves the
    /// tree, or when a view pushed onto its navigation stack covers it.
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        LifecycleView(content: self, handler: action.map { .disappear($0) })
    }

    /// Runs `action` with the old and new values after an update in which
    /// `value` changed. With `initial`, it also runs when the view first
    /// appears, with the value as both.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        LifecycleView(
            content: self,
            handler: .change(ChangeObserver(value: value, initial: initial, action: action)))
    }

    /// Runs `action` after an update in which `value` changed. With
    /// `initial`, it also runs when the view first appears.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        onChange(of: value, initial: initial) { _, _ in action() }
    }

    /// Starts `action` when the view appears, and cancels it if the view
    /// leaves the screen before it finishes.
    ///
    /// The action runs on the main actor when it is written in a view.
    /// ``ViewHost/waitForTasks()`` waits for it, and ``ViewHost/pendingTaskCount``
    /// counts it until it finishes.
    public func task(
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        LifecycleView(
            content: self,
            handler: .task(
                TaskRequest(
                    name: name ?? "View.task @ \(file):\(line)", priority: priority,
                    action: action, id: nil, isSameID: { _ in true })))
    }

    /// Starts `action` when the view appears and again whenever `id`
    /// changes, cancelling the previous run. The action is cancelled if the
    /// view leaves the screen before it finishes.
    public func task<T: Equatable>(
        id: T,
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void
    ) -> some View {
        LifecycleView(
            content: self,
            handler: .task(
                TaskRequest(
                    name: name ?? "View.task @ \(file):\(line)", priority: priority,
                    action: action, id: id, isSameID: { ($0 as? T) == id })))
    }
}

/// What a lifecycle modifier asks for.
enum LifecycleHandler {
    case appear(() -> Void)
    case disappear(() -> Void)
    case task(TaskRequest)
    case change(ChangeObserver)
}

/// The work of a `task` modifier.
struct TaskRequest {
    let name: String
    let priority: TaskPriority
    let action: @isolated(any) () async -> Void
    /// The `id` of `task(id:)`, or `nil`.
    let id: Any?
    /// Whether an earlier `id` equals this one.
    let isSameID: (Any?) -> Bool
}

/// The value an `onChange(of:)` modifier watches, and its action.
struct ChangeObserver {
    let value: Any
    /// The action to run, given the value of the last update, or `nil` if
    /// nothing should run.
    let actionAfter: (_ previous: Any?) -> (() -> Void)?

    init<V: Equatable>(value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.value = value
        actionAfter = { previous in
            guard let previous = previous as? V else {
                // The view is new.
                return initial ? { action(value, value) } : nil
            }
            return previous == value ? nil : { action(previous, value) }
        }
    }
}

/// A view whose appearance, disappearance, or value the host acts on.
struct LifecycleView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let handler: LifecycleHandler?

    var body: Never {
        fatalError("LifecycleView is a primitive view and has no body.")
    }
}

extension LifecycleView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        guard let handler else { return evaluator.evaluate(content, at: path) }
        // Recorded before the content, so that a view's modifiers act
        // before those of the views inside it. Assumed: SwiftUI calls a
        // parent's onAppear before its children's.
        let index = evaluator.lifecycle.begin(handler, at: path)
        let nodes = evaluator.evaluate(content, at: path)
        evaluator.lifecycle.end(index, nodes: nodes)
        return nodes
    }
}

// MARK: - Recording

/// The lifecycle modifiers that one evaluation of the tree saw, in tree
/// order.
@MainActor
final class LifecycleRecord {
    struct Entry {
        /// The modifier's structural position, and which of the modifiers
        /// at that position it is.
        let key: String
        let handler: LifecycleHandler
        /// The nodes the modifier's content resolved to.
        var nodeIDs: [NodeID] = []
    }

    private(set) var entries: [Entry] = []
    private var counts: [String: Int] = [:]

    func begin(_ handler: LifecycleHandler, at path: ViewPath) -> Int {
        let position = path.id.rawValue
        let occurrence = counts[position, default: 0]
        counts[position] = occurrence + 1
        entries.append(Entry(key: "\(position)|\(occurrence)", handler: handler))
        return entries.count - 1
    }

    func end(_ index: Int, nodes: [ViewNode]) {
        entries[index].nodeIDs = nodes.map(\.id)
    }
}

// MARK: - Acting

/// Runs lifecycle actions and keeps `task` work for a ``ViewHost``.
///
/// A view is on screen when a node it resolved to is in the tree after an
/// update. A navigation stack evaluates the screens beneath its top one, so
/// their views keep their state, but their nodes are not in the tree, so
/// they are not on screen. Assumed: a modifier on several views, such as a
/// `Group`'s, acts once for all of them, and a modifier on content with no
/// nodes never appears.
@MainActor
final class ViewLifecycle {
    private struct RunningTask {
        let handle: Task<Void, Never>
        let run: Int
    }

    /// The appear, disappear, and task modifiers on screen, in tree order.
    private var onScreen: [LifecycleRecord.Entry] = []
    /// The last value of each `onChange(of:)`, by key.
    private var changeValues: [String: Any] = [:]
    /// The `id` each `task(id:)` on screen last started with.
    private var taskIDs: [String: Any] = [:]
    private var tasks: [String: RunningTask] = [:]
    private var runs = 0

    var pendingTaskCount: Int { tasks.count }

    /// One of the tasks that has not finished, if any.
    var somePendingTask: Task<Void, Never>? { tasks.values.first?.handle }

    isolated deinit {
        for task in tasks.values { task.handle.cancel() }
    }

    /// Acts on an evaluation whose resolved tree is `tree`: cancels the
    /// tasks of views that left the screen and starts those of views that
    /// arrived, then runs onDisappear, onAppear, and onChange actions, in
    /// that order.
    func apply(_ record: LifecycleRecord, to tree: ViewNode) {
        guard !record.entries.isEmpty || !onScreen.isEmpty || !changeValues.isEmpty else { return }
        let present = Set(tree.allNodes.map(\.id))
        let appeared = record.entries.filter { entry in
            if case .change = entry.handler { return false }
            return entry.nodeIDs.contains(where: present.contains)
        }
        let appearedKeys = Set(appeared.map(\.key))
        let previousKeys = Set(onScreen.map(\.key))
        var actions: [() -> Void] = []

        for entry in onScreen where !appearedKeys.contains(entry.key) {
            switch entry.handler {
            case .disappear(let action): actions.append(action)
            case .task: cancelTask(entry.key)
            case .appear, .change: break
            }
        }
        for entry in appeared {
            let isNew = !previousKeys.contains(entry.key)
            switch entry.handler {
            case .appear(let action) where isNew:
                actions.append(action)
            case .task(let request):
                if isNew || !request.isSameID(taskIDs[entry.key]) {
                    startTask(request, key: entry.key)
                }
                taskIDs[entry.key] = request.id
            default:
                break
            }
        }
        var values: [String: Any] = [:]
        for entry in record.entries {
            guard case .change(let observer) = entry.handler else { continue }
            if let action = observer.actionAfter(changeValues[entry.key]) { actions.append(action) }
            values[entry.key] = observer.value
        }
        changeValues = values
        onScreen = appeared

        for action in actions { action() }
    }

    private func startTask(_ request: TaskRequest, key: String) {
        tasks[key]?.handle.cancel()
        runs += 1
        let run = runs
        let action = request.action
        let handle = Task(name: request.name, priority: request.priority) {
            @MainActor [weak self] in
            await action()
            self?.finishTask(key, run: run)
        }
        tasks[key] = RunningTask(handle: handle, run: run)
    }

    private func finishTask(_ key: String, run: Int) {
        if tasks[key]?.run == run { tasks[key] = nil }
    }

    private func cancelTask(_ key: String) {
        tasks.removeValue(forKey: key)?.handle.cancel()
        taskIDs[key] = nil
    }
}
