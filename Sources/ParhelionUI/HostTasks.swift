#if canImport(Foundation)
import Foundation
#endif

extension ViewHost {
    /// How many `task` actions of the views on screen have not finished.
    public var pendingTaskCount: Int { lifecycle.pendingTaskCount }

    /// Waits until every `task` action of the views on screen has finished,
    /// updating the tree as they change state. Tasks that start meanwhile,
    /// for example because a task's change showed a new view, are waited
    /// for too, so this does not return while a task runs forever.
    public func waitForTasks() async {
        update()
        while let task = lifecycle.somePendingTask {
            await task.value
            update()
        }
    }

    /// Runs main-actor work, such as `task` actions, from synchronous code
    /// on the main thread, updating the tree as the work changes state,
    /// until every `task` action has finished or `deadline` passes.
    ///
    /// - Returns: Whether every task finished.
    @discardableResult
    func runTasks(until deadline: Date) -> Bool {
        update()
        while pendingTaskCount > 0 {
            guard Date() < deadline else { return false }
            _ = RunLoop.main.run(mode: .default, before: deadline)
            update()
        }
        return true
    }
}
