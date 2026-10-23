/// Decides when the window host presents, how long it waits for the app's
/// frame, and what time each tick asks the app to draw for.
///
/// The host owns the clock. After each present, which blocks until the
/// display refreshes when vsync works, it sends the app a tick whose target
/// is the moment the next frame will be on screen: the present time plus
/// ``framesPerTick`` refresh periods. It then waits for the app's answer
/// until shortly before that refresh, uploads the frame, and presents again.
/// A frame that misses its refresh is shown at the next one, and the
/// previous frame stays on screen meanwhile, so motion stays on a straight
/// line even when a frame is late.
///
/// One tick is outstanding at a time. ``framesPerTick`` is 1 while the app
/// answers within a refresh, and grows for an app too slow for that, such
/// as one whose framework is built without optimization, so its frames are
/// shown for equal numbers of refreshes instead of an uneven mix.
///
/// The app is shown no faster than the screen it simulates: on a 240 Hz
/// display, each frame of a 120 Hz iPhone stays up for two refreshes. See
/// ``setMaximumFramesPerSecond(_:)``.
///
/// All times are nanoseconds of the clock the app and host share.
public struct FramePacer: Equatable, Sendable {
    /// The display's refresh period.
    public private(set) var refreshPeriod: UInt64 = Self.defaultRefreshPeriod
    /// Whether presenting blocks until the display refreshes. When it does
    /// not, the host waits for each refresh itself; see
    /// ``nextPresentTime(after:now:)``.
    public private(set) var hasVSync: Bool
    /// How many refreshes each of the app's frames is shown for.
    public private(set) var framesPerTick = 1
    /// The fewest refreshes each frame is shown for, so that the app runs no
    /// faster than the simulated screen.
    public private(set) var minimumFramesPerTick = 1
    /// The target time of the tick the app has not answered yet.
    public private(set) var outstandingTarget: UInt64?

    private var maximumFramesPerSecond: Int?
    private var tickSentAt: UInt64 = 0
    private var lastPresent: UInt64?
    private var shortIntervals = 0
    /// The most recent times from sending a tick to receiving its answer.
    private var roundTrips: [UInt64] = []
    /// The longest recent upload, which the frame deadline leaves room for.
    private var uploadCost: UInt64 = 1_000_000

    /// 60 Hz, for displays that do not report a refresh rate.
    public static let defaultRefreshPeriod: UInt64 = 16_666_667
    /// How many round trips ``framesPerTick`` is chosen from.
    static let roundTripWindow = 16
    /// How many presents in a row must return well before a refresh before
    /// the pacer decides that vsync is not real.
    static let shortIntervalLimit = 5
    /// The most refreshes one frame is shown for.
    static let maximumFramesPerTick = 8

    public init(vsyncEnabled: Bool) {
        hasVSync = vsyncEnabled
    }

    /// The refresh period of a display mode, from SDL's rational refresh
    /// rate, or its approximate rate when the rational one is missing, or
    /// 60 Hz when the display reports neither.
    public static func refreshPeriod(numerator: Int32, denominator: Int32, rate: Float) -> UInt64 {
        if numerator > 0 {
            return UInt64(max(denominator, 1)) * 1_000_000_000 / UInt64(numerator)
        }
        if rate > 1 {
            return UInt64((1e9 / Double(rate)).rounded())
        }
        return defaultRefreshPeriod
    }

    /// Changes the refresh period, as when the window moves to another
    /// display.
    public mutating func setRefreshPeriod(_ period: UInt64) {
        guard period > 0, period != refreshPeriod else { return }
        refreshPeriod = period
        updateMinimumFramesPerTick()
    }

    /// Shows the app no faster than `rate` frames per second, the simulated
    /// screen's rate, or as fast as the display refreshes for `nil`.
    ///
    /// Each frame stays up for the fewest whole refreshes that keep the rate
    /// at or below `rate`: two at 240 Hz for a 120 Hz screen, and one on a
    /// display no faster than the screen. On a display whose rate is not a
    /// multiple of the screen's, the app runs slower than the screen rather
    /// than faster: 72 Hz on a 144 Hz display for a 120 Hz screen.
    public mutating func setMaximumFramesPerSecond(_ rate: Int?) {
        guard rate != maximumFramesPerSecond else { return }
        maximumFramesPerSecond = rate
        updateMinimumFramesPerTick()
    }

    private mutating func updateMinimumFramesPerTick() {
        minimumFramesPerTick = Self.minimumFramesPerTick(
            refreshPeriod: refreshPeriod, maximumFramesPerSecond: maximumFramesPerSecond)
        roundTrips.removeAll()
        framesPerTick = minimumFramesPerTick
    }

    static func minimumFramesPerTick(refreshPeriod: UInt64, maximumFramesPerSecond: Int?) -> Int {
        guard let rate = maximumFramesPerSecond, rate > 0 else { return 1 }
        // A display up to 1% faster than a multiple of the screen's rate,
        // such as 120.5 Hz for a 120 Hz screen, counts as that multiple.
        let screenPeriod = 1_000_000_000 / UInt64(rate)
        let shortest = screenPeriod - screenPeriod / 100
        let refreshes = (shortest + refreshPeriod - 1) / refreshPeriod
        return Int(min(max(refreshes, 1), UInt64(maximumFramesPerTick)))
    }

    /// Forgets the app's timing, for a new app.
    public mutating func reset() {
        outstandingTarget = nil
        roundTrips.removeAll()
        framesPerTick = minimumFramesPerTick
    }

    /// The time a tick sent right after a present at `time` asks the app to
    /// draw for: when the frame it draws will be on screen.
    public func targetTime(afterPresentAt time: UInt64) -> UInt64 {
        time + UInt64(framesPerTick) * refreshPeriod
    }

    /// How long after a present at `time` the host waits for the app's
    /// frame before presenting what it has. It leaves room to upload the
    /// frame before the refresh.
    public func frameDeadline(afterPresentAt time: UInt64) -> UInt64 {
        targetTime(afterPresentAt: time) - margin
    }

    /// The room left before a refresh for uploading a frame: the longest
    /// recent upload and half a millisecond, but at most half a period.
    var margin: UInt64 {
        min(uploadCost + 500_000, refreshPeriod / 2)
    }

    /// Without vsync: when to present next, one period after the last
    /// present, or now if that time has passed.
    public func nextPresentTime(after last: UInt64, now: UInt64) -> UInt64 {
        max(last + refreshPeriod, now)
    }

    /// The first refresh after a present at `last` that keeps the app at or
    /// below the simulated screen's rate: the next one, or a later one on a
    /// display faster than the screen.
    public func earliestRefresh(after last: UInt64) -> UInt64 {
        last + UInt64(minimumFramesPerTick) * refreshPeriod
    }

    /// When to present a frame so that it reaches the screen at `refresh`
    /// and not sooner, or now if that time has passed.
    ///
    /// With vsync, presenting waits for the next refresh, so the frame goes
    /// out a quarter period after the refresh before. Without, it goes out
    /// at `refresh`. A fast app answers long before the refresh at
    /// ``earliestRefresh(after:)``, and without the wait it would run at the
    /// display's rate instead of the screen's.
    public func presentTime(forRefreshAt refresh: UInt64, now: UInt64) -> UInt64 {
        let time = hasVSync ? refresh - refreshPeriod + refreshPeriod / 4 : refresh
        return max(time, now)
    }

    /// Records a present, which returned at `time`. If vsync is on but
    /// presents keep returning well before the refresh they were for, the
    /// driver is not waiting for the display, as with SDL's offscreen
    /// driver, and the pacer switches to waiting itself. A present is for
    /// the refresh after the last one, or for `refresh` when the frame was
    /// held until shortly before it; see ``presentTime(forRefreshAt:now:)``.
    public mutating func notePresented(at time: UInt64, heldFor refresh: UInt64? = nil) {
        defer { lastPresent = time }
        guard hasVSync, let lastPresent else { return }
        let refresh = refresh ?? lastPresent + refreshPeriod
        if time + refreshPeriod / 2 < refresh {
            shortIntervals += 1
            if shortIntervals >= Self.shortIntervalLimit { hasVSync = false }
        } else {
            shortIntervals = 0
        }
    }

    /// Records how long an upload took.
    public mutating func noteUpload(duration: UInt64) {
        // Decay slowly, so one fast upload does not shrink the margin.
        uploadCost = max(duration, uploadCost - uploadCost / 16)
    }

    /// Whether to send a tick now: none is outstanding, or the outstanding
    /// one is overdue, which happens if the app was busy or its answer was
    /// lost.
    public func shouldTick(now: UInt64) -> Bool {
        guard outstandingTarget != nil else { return true }
        return now - tickSentAt > max(100_000_000, 8 * refreshPeriod)
    }

    /// Records a tick sent at `time` for `target`.
    public mutating func noteTickSent(target: UInt64, at time: UInt64) {
        outstandingTarget = target
        tickSentAt = time
    }

    /// Records the app's answer to the tick for `target`, which arrived at
    /// `time`, and chooses how many refreshes the next frames are shown for.
    public mutating func noteAnswer(target: UInt64, at time: UInt64) {
        guard target == outstandingTarget else { return }
        outstandingTarget = nil
        roundTrips.append(time - tickSentAt)
        if roundTrips.count > Self.roundTripWindow { roundTrips.removeFirst() }
        // The slowest recent answer decides, so the choice does not flip
        // from frame to frame.
        let slowest = roundTrips.max() ?? 0
        let needed = (slowest + margin + refreshPeriod - 1) / refreshPeriod
        framesPerTick = Int(
            min(max(needed, UInt64(minimumFramesPerTick)), UInt64(Self.maximumFramesPerTick)))
    }
}
