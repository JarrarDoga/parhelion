import Observation

#if canImport(Foundation)
import Foundation
#endif

/// Turns changes to the `@Observable` properties that views read into
/// updates.
///
/// Each evaluation of the tree runs inside the toolchain's
/// `withObservationTracking`, which records every property of an observable
/// object that a `body`, a binding, or a presented view reads. The first
/// change to any of them marks the host as needing an update. Tracking ends
/// with that change, and the next evaluation records the properties again.
///
/// Observation starts watching only after the evaluation returns, so the
/// previous evaluation's tracking stays active until then: a change that
/// another thread makes during an evaluation, to a property that the
/// previous evaluation read too, still requests an update. A property that
/// an evaluation reads for the first time and another thread changes before
/// the evaluation returns is missed until the next update.
@MainActor
final class ObservationScope {
    /// Two observable values, one read by every other evaluation. Observation
    /// keeps an evaluation's observers registered with each object it read
    /// until one of the properties changes, so once a newer evaluation is
    /// tracked, changing the value the older one read ends its tracking,
    /// even when the app changed only `@State`.
    private let generations = (EvaluationGeneration(), EvaluationGeneration())
    private var current: Invalidation?
    private var evaluations = 0

    /// Runs `evaluate`, and marks `host` as needing an update when an
    /// observable property it read changes.
    func track<Result>(for host: ViewHost, _ evaluate: () -> Result) -> Result {
        evaluations += 1
        let (own, previous) =
            evaluations.isMultiple(of: 2)
            ? (generations.0, generations.1) : (generations.1, generations.0)
        let invalidation = Invalidation(host: host)
        let result = withObservationTracking {
            _ = own.value
            return evaluate()
        } onChange: {
            invalidation.fire()
        }
        // This evaluation is tracked now, so the previous one can stop.
        current?.cancel()
        current = invalidation
        previous.value += 1
        return result
    }
}

@Observable
final class EvaluationGeneration {
    var value = 0
}

/// One evaluation's request for an update. Observation calls it on the
/// thread that makes the change, before the change is made.
final class Invalidation: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    /// Read only on the main thread.
    private weak var host: ViewHost?

    init(host: ViewHost) {
        self.host = host
    }

    /// Stops a later change from requesting an update, because a newer
    /// evaluation tracks the properties now.
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isFinished = true
    }

    func fire() {
        lock.lock()
        let shouldUpdate = !isFinished
        isFinished = true
        lock.unlock()
        guard shouldUpdate else { return }
        if Self.isOnMainActor {
            // Synchronously, so that a change inside `withAnimation`
            // animates.
            MainActor.assumeIsolated { host?.setNeedsUpdate() }
        } else {
            // Applied on the main thread's next turn, after the change.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.host?.setNeedsUpdate() }
            }
        }
    }

    /// Whether the caller runs on the main actor.
    private static var isOnMainActor: Bool {
        Thread.isMainThread || DispatchQueue.getSpecific(key: MainQueueMark.shared.key) == true
    }
}

/// A mark on the main queue. Where an async `main` hands the main queue to
/// other threads, as in Swift Testing, main-actor work runs on the main
/// queue but not on the main thread.
private final class MainQueueMark: @unchecked Sendable {
    static let shared = MainQueueMark()
    let key = DispatchSpecificKey<Bool>()

    private init() {
        DispatchQueue.main.setSpecific(key: key, value: true)
    }
}
