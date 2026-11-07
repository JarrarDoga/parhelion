#if canImport(Glibc)
#if canImport(Foundation)
import Foundation
#endif
import ParhelionPreview

#if compiler(>=6.3)
@_spi(ExperimentalCustomExecutors) @_spi(ExperimentalScheduling) import _Concurrency
#endif

/// The manual clock: a host that owns the app's time, so that waiting moves
/// the clock instead of sleeping.
///
/// A process started with `PARHELION_MANUAL_CLOCK=1` replaces Swift's main and
/// default executors before anything runs (see
/// `docs/adr/0011-manual-clock.md`). The replacements hold every
/// `Task.sleep` wake-up at "virtual now plus the delay" and run all other work
/// serially on the main thread. ``advance(by:moving:settled:)`` then releases
/// the wake-ups in deadline order, settling the app after each one, with no
/// real waiting.
///
/// Swift offers this only as SPI since 6.3. On a toolchain without it, or
/// when the process did not ask for it, ``install()`` returns `false`, and
/// time stays real.
enum ManualClock {
    /// Whether this toolchain can replace the executors.
    static var isSupported: Bool {
        #if compiler(>=6.3)
        true
        #else
        false
        #endif
    }

    /// Whether the process asked for the manual clock and this toolchain can
    /// provide it.
    static var isRequested: Bool {
        isSupported && ProcessInfo.processInfo.environment[previewManualClockEnvironmentKey] == "1"
    }

    /// Whether the executors are replaced.
    nonisolated(unsafe) private(set) static var isInstalled = false

    /// Replaces the main and default executors when the process asked for the
    /// manual clock. Call it first thing in `main`: Swift accepts new
    /// executors only before the first job is enqueued.
    ///
    /// - Returns: Whether the clock is manual.
    @discardableResult
    static func install() -> Bool {
        guard !isInstalled, isRequested else { return isInstalled }
        #if compiler(>=6.3)
        _createExecutors(factory: HostClockFactory.self)
        isInstalled = true
        #endif
        return isInstalled
    }

    /// The time the clock shows, in seconds since it was installed.
    static var now: TimeInterval {
        #if compiler(>=6.3)
        return isInstalled ? HostClockExecutor.shared.now : 0
        #else
        return 0
        #endif
    }

    /// The time of the earliest sleep that is waiting, if any.
    static var nextDeadline: TimeInterval? {
        #if compiler(>=6.3)
        return isInstalled ? HostClockExecutor.shared.nextDeadline : nil
        #else
        return nil
        #endif
    }

    /// How many sleeps are waiting for the clock.
    static var pendingSleepCount: Int {
        #if compiler(>=6.3)
        return isInstalled ? HostClockExecutor.shared.pendingCount : 0
        #else
        return 0
        #endif
    }

    /// Moves the clock `interval` seconds on, waking the sleeps that fall due
    /// in deadline order (those with the same deadline in the order they went
    /// to sleep).
    ///
    /// - Parameters:
    ///   - moving: Called with the seconds the clock is about to move, before
    ///     each wake-up and once more for the rest of the interval, so that
    ///     animations see time pass.
    ///   - settled: Called after the app has run all the work a wake-up
    ///     started, and after the last step.
    static func advance(
        by interval: TimeInterval, moving: (TimeInterval) -> Void, settled: () -> Void
    ) {
        #if compiler(>=6.3)
        guard isInstalled else { return }
        HostClockExecutor.shared.advance(by: interval, moving: moving, settled: settled)
        #endif
    }

    /// Runs the work that is waiting, on the main thread, without moving the
    /// clock.
    static func settle() {
        #if compiler(>=6.3)
        if isInstalled { HostClockMainExecutor.shared.drain() }
        #endif
    }
}

#if compiler(>=6.3)

/// Replaces the platform executors. Swift calls the properties once, from
/// `_createExecutors(factory:)`.
private struct HostClockFactory: ExecutorFactory {
    static var mainExecutor: any MainExecutor { HostClockMainExecutor.shared }
    static var defaultExecutor: any TaskExecutor { HostClockExecutor.shared }
}

/// The main actor's executor. It queues main-actor jobs in a FIFO, and the
/// manual clock runs them, on the main thread, after each step in time. Work
/// that arrives while nobody advances time still runs, from the main queue.
private final class HostClockMainExecutor: MainExecutor, @unchecked Sendable {
    static let shared = HostClockMainExecutor()

    private let base = PlatformExecutorFactory.mainExecutor
    private let lock = NSLock()
    private var queue: [UnownedJob] = []
    private var drainPosted = false

    func run() throws { try base.run() }
    func stop() { base.stop() }
    func checkIsolated() { base.checkIsolated() }
    var isMainExecutor: Bool { true }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let post = lock.withLock {
            queue.append(job)
            defer { drainPosted = true }
            return !drainPosted
        }
        if post { DispatchQueue.main.async { self.drain() } }
    }

    /// Runs main-actor jobs and global jobs until neither has any left.
    /// Call it on the main thread only.
    func drain() {
        while true {
            if let job = lock.withLock({ () -> UnownedJob? in
                if queue.isEmpty {
                    drainPosted = false
                    return nil
                }
                return queue.removeFirst()
            }) {
                job.runSynchronously(on: asUnownedSerialExecutor())
            } else if let job = HostClockExecutor.shared.takeJob() {
                job.runSynchronously(on: HostClockExecutor.shared.asUnownedTaskExecutor())
            } else {
                return
            }
        }
    }
}

/// The default executor, which runs everything that is not on the main
/// actor, and which `Task.sleep` asks to wake a sleeper at a time. It holds
/// each wake-up until the clock reaches it, and queues other jobs for the
/// main thread.
private final class HostClockExecutor: TaskExecutor, SchedulingExecutor, @unchecked Sendable {
    static let shared = HostClockExecutor()

    private struct Sleep {
        var deadline: Int64
        var order: Int
        var job: UnownedJob
    }

    private let lock = NSLock()
    /// The clock, in milliseconds. Sleeps are held to the millisecond.
    private var milliseconds: Int64 = 0
    private var sleeps: [Sleep] = []
    private var sleepCount = 0
    private var queue: [UnownedJob] = []

    var now: TimeInterval { lock.withLock { Double(milliseconds) / 1000 } }

    var nextDeadline: TimeInterval? {
        lock.withLock { sleeps.map(\.deadline).min().map { Double($0) / 1000 } }
    }

    var pendingCount: Int { lock.withLock { sleeps.count } }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        lock.withLock { queue.append(job) }
        DispatchQueue.main.async { HostClockMainExecutor.shared.drain() }
    }

    func takeJob() -> UnownedJob? {
        lock.withLock { queue.isEmpty ? nil : queue.removeFirst() }
    }

    func enqueue<C: Clock>(
        _ job: consuming ExecutorJob, at instant: C.Instant, tolerance: C.Duration?, clock: C
    ) {
        let job = UnownedJob(job)
        // Only the built-in clocks reach here, and they measure in `Duration`.
        // The deadline was read before this call, so the delay comes out a few
        // microseconds short: round it up to the millisecond.
        var delay: Int64 = 0
        if let duration = clock.now.duration(to: instant) as? Duration {
            let (seconds, attoseconds) = duration.components
            let value = Double(seconds) * 1e3 + Double(attoseconds) / 1e15
            delay = Int64(max(value, 0).rounded(.up))
        }
        lock.withLock {
            sleepCount += 1
            sleeps.append(Sleep(deadline: milliseconds + delay, order: sleepCount, job: job))
        }
    }

    func advance(by interval: TimeInterval, moving: (TimeInterval) -> Void, settled: () -> Void) {
        let target = lock.withLock { milliseconds + Int64((max(interval, 0) * 1000).rounded()) }
        HostClockMainExecutor.shared.drain()
        settled()
        while let next = takeSleep(due: target) {
            moving(Double(next.elapsed) / 1000)
            // The wake-up only resumes the sleeper, which then queues itself
            // on its own executor; draining runs it.
            next.job.runSynchronously(on: asUnownedTaskExecutor())
            HostClockMainExecutor.shared.drain()
            settled()
        }
        let rest = lock.withLock { () -> Int64 in
            defer { milliseconds = target }
            return target - milliseconds
        }
        if rest > 0 {
            moving(Double(rest) / 1000)
            HostClockMainExecutor.shared.drain()
            settled()
        }
    }

    /// Takes the earliest sleep due by `target`, and moves the clock to its
    /// deadline.
    private func takeSleep(due target: Int64) -> (job: UnownedJob, elapsed: Int64)? {
        lock.withLock {
            guard
                let index = sleeps.indices.filter({ sleeps[$0].deadline <= target })
                    .min(by: {
                        (sleeps[$0].deadline, sleeps[$0].order)
                            < (sleeps[$1].deadline, sleeps[$1].order)
                    })
            else { return nil }
            let sleep = sleeps.remove(at: index)
            let elapsed = max(sleep.deadline - milliseconds, 0)
            milliseconds = max(sleep.deadline, milliseconds)
            return (sleep.job, elapsed)
        }
    }
}

#endif
#endif
