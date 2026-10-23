#if canImport(Foundation)
import Foundation
#endif

extension ViewHost {
    /// How many `task` actions have not returned: those of the views on
    /// screen, and cancelled ones that are still finishing.
    public var pendingTaskCount: Int { lifecycle.pendingTaskCount }

    /// Waits until every `task` action has returned, including cancelled
    /// ones, updating the tree as they change state, so that no task changes
    /// state after this returns. Tasks that start meanwhile, for example
    /// because a task's change showed a new view, are waited for too, so
    /// this does not return while a task runs forever.
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
