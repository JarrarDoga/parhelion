#if canImport(Foundation)
import Foundation
#endif

extension ViewHost {
    /// Whether the app's clock is manual: the process replaced Swift's
    /// executors, so `Task.sleep` waits for ``advanceClock(by:)`` instead of
    /// for real time.
    public var hasManualClock: Bool {
        #if canImport(Glibc)
        ManualClock.isInstalled
        #else
        false
        #endif
    }

    /// The seconds from now until the next `Task.sleep` wakes, or `nil` if
    /// none is waiting or the clock is not manual.
    public var secondsUntilNextWake: TimeInterval? {
        #if canImport(Glibc)
        ManualClock.nextDeadline.map { max($0 - ManualClock.now, 0) }
        #else
        nil
        #endif
    }

    /// Moves the app's clock `seconds` on without waiting, as a person would
    /// see the app after that long.
    ///
    /// Animations and scroll momentum advance with ``advanceTime(by:)``. When
    /// the clock is manual, each `Task.sleep` that falls due wakes at its own
    /// deadline, in deadline order, and the app settles (main-actor work runs
    /// and the tree updates) before the next one. Work that waits for
    /// something other than time, such as a socket, gets a short moment of
    /// real time once no sleep is left. With a real clock, this only advances
    /// ``time``.
    public func advanceClock(by seconds: TimeInterval) {
        update()
        #if canImport(Glibc)
        guard ManualClock.isInstalled else {
            advanceTime(by: seconds)
            return
        }
        ManualClock.advance(
            by: seconds, moving: { advanceTime(by: $0) }, settled: { update() })
        // A task that waits for something other than time needs real time. A
        // sleeping one is not waiting for that, so wait only when none sleeps.
        let deadline = Date(timeIntervalSinceNow: Self.realTimeAllowance)
        while pendingTaskCount > 0, ManualClock.pendingSleepCount == 0, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            ManualClock.advance(by: 0, moving: { advanceTime(by: $0) }, settled: { update() })
        }
        #else
        advanceTime(by: seconds)
        #endif
    }

    /// How long ``advanceClock(by:)`` lets tasks that wait for something
    /// other than time run, in seconds of real time.
    static let realTimeAllowance: TimeInterval = 0.25
}
