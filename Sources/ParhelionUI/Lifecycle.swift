#if canImport(Foundation)
import Foundation
#endif

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
    /// counts it until it returns, even after it is cancelled: cancelling
    /// asks it to stop, and the changes it makes before it returns apply.
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

/// Which lifecycle modifier an entry is: its structural position, and
/// which of the modifiers at that position it is, outermost first.
struct LifecycleKey: Hashable {
    let position: NodeID
    let occurrence: Int
}

/// The lifecycle modifiers that one evaluation of the tree saw, in tree
/// order.
@MainActor
final class LifecycleRecord {
    struct Entry {
        let key: LifecycleKey
        let handler: LifecycleHandler
        /// The nodes the modifier's content resolved to.
        var nodeIDs: [NodeID] = []
    }

    private(set) var entries: [Entry] = []
    private var counts: [NodeID: Int] = [:]

    func begin(_ handler: LifecycleHandler, at path: ViewPath) -> Int {
        let position = path.id
        let occurrence = counts[position, default: 0]
        counts[position] = occurrence + 1
        entries.append(
            Entry(key: LifecycleKey(position: position, occurrence: occurrence), handler: handler))
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
///
/// A task run that is cancelled, because its view left the screen or its
/// `id` changed, keeps running until it returns: cancellation in Swift asks
/// the work to stop but does not stop it. Until then it is pending, so
/// ``ViewHost/waitForTasks()`` waits for it. Its changes apply like any
/// other: a model it changes updates the tree, and `@State` of a view that
/// left the screen went with the view.
@MainActor
final class ViewLifecycle {
    /// The appear, disappear, and task modifiers on screen, in tree order.
    private var onScreen: [LifecycleRecord.Entry] = []
    /// The last value of each `onChange(of:)`.
    private var changeValues: [LifecycleKey: Any] = [:]
    /// The `id` each `task(id:)` on screen last started with.
    private var taskIDs: [LifecycleKey: Any] = [:]
    /// The run of each task modifier on screen.
    private var currentRuns: [LifecycleKey: Int] = [:]
    /// Every run that has not returned yet, including cancelled ones, by
    /// run number.
    private var unfinishedRuns: [Int: Task<Void, Never>] = [:]
    private var runs = 0
    /// What the last update's actions were, for a warning when updates do
    /// not stop.
    private(set) var lastActions: [String] = []
    private var hasWarnedAboutEndlessUpdates = false

    var pendingTaskCount: Int { unfinishedRuns.count }

    /// One of the runs that has not returned, if any.
    var somePendingTask: Task<Void, Never>? { unfinishedRuns.values.first }

    isolated deinit {
        for task in unfinishedRuns.values { task.cancel() }
    }

    /// Acts on an evaluation whose resolved tree is `tree`: cancels the
    /// tasks of views that left the screen and starts those of views that
    /// arrived, then runs onDisappear, onAppear, and onChange actions.
    /// Assumed: SwiftUI does not document this order.
    func apply(_ record: LifecycleRecord, to tree: ViewNode) {
        lastActions = []
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
            case .disappear(let action):
                actions.append(action)
                lastActions.append("onDisappear at \(entry.key.position)")
            case .task: cancelTask(entry.key)
            case .appear, .change: break
            }
        }
        for entry in appeared {
            let isNew = !previousKeys.contains(entry.key)
            switch entry.handler {
            case .appear(let action) where isNew:
                actions.append(action)
                lastActions.append("onAppear at \(entry.key.position)")
            case .task(let request):
                if isNew || !request.isSameID(taskIDs[entry.key]) {
                    startTask(request, key: entry.key)
                }
                taskIDs[entry.key] = request.id
            default:
                break
            }
        }
        var values: [LifecycleKey: Any] = [:]
        for entry in record.entries {
            guard case .change(let observer) = entry.handler else { continue }
            if let action = observer.actionAfter(changeValues[entry.key]) {
                actions.append(action)
                lastActions.append("onChange(of:) at \(entry.key.position)")
            }
            values[entry.key] = observer.value
        }
        changeValues = values
        onScreen = appeared

        for action in actions { action() }
    }

    /// Writes a warning, once, that updates did not stop.
    func warnAboutEndlessUpdates(after passes: Int) {
        guard !hasWarnedAboutEndlessUpdates else { return }
        hasWarnedAboutEndlessUpdates = true
        let cause =
            lastActions.isEmpty
            ? "A view may change state while its body is evaluated."
            : "The last update ran \(lastActions.joined(separator: ", ")), which changed state again."
        FileHandle.standardError.write(
            Data(
                "parhelion: state changed in each of \(passes) updates in a row, so the host stopped updating until the next change. \(cause)\n"
                    .utf8))
    }

    private func startTask(_ request: TaskRequest, key: LifecycleKey) {
        cancelTask(key)
        runs += 1
        let run = runs
        let action = request.action
        let handle = Task(name: request.name, priority: request.priority) {
            @MainActor [weak self] in
            await action()
            self?.unfinishedRuns[run] = nil
        }
        currentRuns[key] = run
        unfinishedRuns[run] = handle
    }

    /// Cancels the current run of a task modifier. The run stays pending
    /// until it returns.
    private func cancelTask(_ key: LifecycleKey) {
        if let run = currentRuns.removeValue(forKey: key) { unfinishedRuns[run]?.cancel() }
        taskIDs[key] = nil
    }
}
