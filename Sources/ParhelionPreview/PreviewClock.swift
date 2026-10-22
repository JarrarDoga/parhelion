#if canImport(Glibc)
import Glibc
#endif

/// The clock that ticks and frame times use: nanoseconds of
/// `CLOCK_MONOTONIC`.
///
/// Every process on a machine reads the same monotonic clock, so a time the
/// host sends means the same moment to the app. Swift's `ContinuousClock`
/// may use a different clock on Linux, so the protocol does not use it.
public enum PreviewClock {
    /// The current time in nanoseconds.
    public static func now() -> UInt64 {
        #if canImport(Glibc)
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
        #else
        return 0
        #endif
    }

    /// Nanoseconds as seconds.
    public static func seconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1e9
    }

    /// Nanoseconds as milliseconds, for logs.
    public static func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1e6
    }
}

/// Keeps an app's animation clock in step with the host's clock.
///
/// `ViewHost` time advances only when told to. The timeline remembers which
/// moment of ``PreviewClock`` the app's clock currently shows, and says how
/// far to advance it to reach a later moment: the target time of a tick, or
/// the current time when input arrives while nothing moves. It never goes
/// backward, so a late tick or input that arrives out of order moves
/// nothing.
public struct PreviewTimeline: Equatable, Sendable {
    /// The moment the app's clock shows, in ``PreviewClock`` nanoseconds.
    public private(set) var current: UInt64

    public init(start: UInt64) {
        current = start
    }

    /// Moves the timeline to `time` and returns the seconds to advance the
    /// app's clock by, which is 0 if `time` is not later than ``current``.
    public mutating func advance(to time: UInt64) -> Double {
        guard time > current else { return 0 }
        defer { current = time }
        return PreviewClock.seconds(time - current)
    }
}
