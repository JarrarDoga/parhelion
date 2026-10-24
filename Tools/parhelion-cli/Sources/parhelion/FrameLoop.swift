import Foundation
import ParhelionPreview
import ParhelionTooling

/// Something that shows the app's frames and collects input for it: the
/// preview window, web pages, or both.
///
/// Showing a frame has two steps, so that ``FrameLoop`` can time them:
/// ``upload(_:)`` copies the frame's damaged pixels, and ``present()``
/// shows them. With vsync, presenting waits for the display to refresh.
protocol PreviewSurface: AnyObject {
    /// Whether ``present()`` waits for the display to refresh.
    var hasVSync: Bool { get }
    /// The time between refreshes, in nanoseconds.
    var refreshPeriod: UInt64 { get }
    /// A function other threads can call to wake ``events(waitingUpTo:)``.
    var waker: @Sendable () -> Void { get }
    /// Waits up to `timeout` seconds for the first event, or until woken,
    /// then takes every event already queued without waiting. A timeout of
    /// 0 does not wait.
    func events(waitingUpTo timeout: Double) -> [SurfaceEvent]
    /// Copies a frame's damaged pixels. Returns `false` for a frame without
    /// pixels.
    func upload(_ frame: ReceivedFrame) throws -> Bool
    func present()
    /// Waits precisely, for pacing without vsync.
    func delay(nanoseconds: UInt64)
    /// A new app connected, as when hot reload restarts it.
    func show(_ hello: PreviewHello)
    func setStatus(_ status: PreviewStatus)
    /// The simulated device's appearance or text size changed.
    func show(_ appearance: PreviewAppearance)
}

/// What a ``PreviewSurface`` reports.
enum SurfaceEvent {
    /// The user closed the window or interrupted the tool.
    case close
    /// Input to forward to the app.
    case input(HostMessage)
    /// The surface needs drawing again, as after a window was uncovered.
    case redraw
    /// The person asked for another appearance or text size.
    case appearance(PreviewAppearance.Change)
}

/// The simulated device's appearance and text size, shared by the frame
/// loop, which applies changes from the window and pages, and an agent's
/// tools. Each launch of the app starts with it, so it survives hot reload.
final class AppearanceState: @unchecked Sendable {
    private let lock = NSLock()
    private var appearance = PreviewAppearance()
    private var changes = 0

    /// Starts with the setting that `PARHELION_COLOR_SCHEME` and
    /// `PARHELION_DYNAMIC_TYPE_SIZE` name in the tool's own environment, or
    /// light at the Large size.
    init() {
        let environment = ProcessInfo.processInfo.environment
        let change = PreviewAppearance.Change.set(
            colorScheme: environment[previewColorSchemeEnvironmentKey],
            dynamicTypeSize: environment[previewDynamicTypeSizeEnvironmentKey])
        if let start = appearance.applying(change) {
            appearance = start
        } else {
            Self.warn(
                "ignoring \(previewColorSchemeEnvironmentKey) or "
                    + "\(previewDynamicTypeSizeEnvironmentKey): use a color scheme of "
                    + PreviewAppearance.colorSchemes.joined(separator: " or ")
                    + " and a size from "
                    + PreviewAppearance.dynamicTypeSizes.joined(separator: ", ") + ".")
        }
    }

    /// The current setting, and a number that increases with each change.
    var current: (appearance: PreviewAppearance, revision: Int) {
        lock.withLock { (appearance, changes) }
    }

    /// Applies a change, and returns the new setting, or `nil` when the
    /// change names a scheme or a size that does not exist.
    func apply(_ change: PreviewAppearance.Change) -> PreviewAppearance? {
        lock.withLock {
            guard let changed = appearance.applying(change) else { return nil }
            if changed != appearance {
                appearance = changed
                changes += 1
            }
            return changed
        }
    }

    /// The environment variables that start an app with the setting.
    var environment: [String: String] { current.appearance.environment }

    /// Gives a running app the current setting. An app built with an older
    /// Parhelion cannot take it; the message saying so prints once.
    func send(to app: AppConnection?) {
        guard let app else { return }
        guard PreviewAppearance.isSupported(by: app.hello) else {
            let warn = lock.withLock {
                defer { warnedApps.insert(ObjectIdentifier(app)) }
                return !warnedApps.contains(ObjectIdentifier(app))
            }
            if warn {
                Self.warn(
                    "\(app.hello.appName) was built with an older Parhelion, which cannot switch "
                        + "the appearance or text size. Update its Parhelion dependency.")
            }
            return
        }
        app.post(current.appearance.command)
    }

    /// Writes a warning to standard error, because standard output carries
    /// the protocol in `parhelion mcp`.
    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("parhelion: \(message)\n".utf8))
    }

    private var warnedApps: Set<ObjectIdentifier> = []
}

/// The preview's main loop: it forwards input to the app, shows the app's
/// newest frame, and, while the app animates, paces it to the display, or
/// for web pages, to a timer at the simulated screen's frame rate.
///
/// Each ``step(app:idleTimeout:)`` is one pass. While the app animates and
/// draws for the host's clock, a pass waits for the app's answer to the last
/// tick until shortly before the next refresh, uploads it, presents (which
/// waits for the refresh), and sends the next tick. Otherwise a pass blocks
/// until input, a frame, or `idleTimeout`, so an idle preview uses no CPU.
/// ``FramePacer`` holds the timing rules, including the simulated screen's
/// frame rate.
final class FrameLoop {
    private let surface: PreviewSurface
    private let appearance: AppearanceState
    /// The revision of the appearance the surface shows.
    private var shownAppearance = -1
    private var pacer: FramePacer
    /// The app the pacer's timing belongs to.
    private var appIdentity: ObjectIdentifier?
    private var lastPresent: UInt64 = 0
    private var lastTickSent: UInt64 = 0
    private var needsRedraw = false
    private var announcedSoftwarePacing = false

    /// What a pass did.
    enum Step {
        /// The user closed the window.
        case close
        /// The pass finished; `presentedFrame` says whether it showed a new
        /// frame from the app.
        case running(presentedFrame: Bool)
    }

    init(surface: PreviewSurface, appearance: AppearanceState) {
        self.surface = surface
        self.appearance = appearance
        pacer = FramePacer(vsyncEnabled: surface.hasVSync)
        pacer.setRefreshPeriod(surface.refreshPeriod)
    }

    /// Runs one pass of the loop for `app`, which may change between passes
    /// when hot reload starts a new build.
    func step(app: AppConnection?, idleTimeout: Double) throws -> Step {
        if appIdentity != app.map(ObjectIdentifier.init) {
            appIdentity = app.map(ObjectIdentifier.init)
            pacer.reset()
            if let app {
                surface.show(app.hello)
                pacer.setMaximumFramesPerSecond(app.hello.maximumFramesPerSecond)
            }
        }
        pacer.setRefreshPeriod(surface.refreshPeriod)
        // An app that exited mid-animation still says it animates; without
        // this, the loop would present at the refresh rate until a reload.
        let live = app.flatMap { $0.isDisconnected ? nil : $0 }
        if app != nil, live == nil, pacer.outstandingTarget != nil { pacer.reset() }
        let ticking =
            live.map { $0.usesHostClock && ($0.isAnimating || pacer.outstandingTarget != nil) }
            ?? false

        var events: [SurfaceEvent] = []
        if let app, ticking {
            // Wait for the app's answer until the frame deadline, handling
            // input as it arrives. The reader thread wakes the wait.
            let deadline = pacer.frameDeadline(afterPresentAt: lastPresent)
            while !app.hasNews, !app.isDisconnected {
                let now = PreviewClock.now()
                guard deadline > now + 1_000_000 else { break }
                // Whole milliseconds, rounded down, so the wait ends before
                // the deadline.
                events += surface.events(waitingUpTo: Double((deadline - now) / 1_000_000) / 1000)
                if events.contains(where: { if case .close = $0 { true } else { false } }) { break }
            }
            events += surface.events(waitingUpTo: 0)
        } else {
            events = surface.events(waitingUpTo: idleTimeout)
        }
        if handle(events, app: app) { return .close }
        // An agent can change the appearance too, from another thread.
        let current = appearance.current
        if current.revision != shownAppearance {
            shownAppearance = current.revision
            surface.show(current.appearance)
        }

        let answer = app?.takeAnswer()
        if let answer {
            pacer.noteAnswer(target: answer.target, at: answer.arrival)
            if isDebugLogging {
                debugLog(
                    String(
                        format: "answer after %.3f ms, %d refreshes per frame",
                        PreviewClock.milliseconds(answer.arrival - lastTickSent),
                        pacer.framesPerTick))
            }
        }
        var presentedFrame = false
        if let app, let frame = app.takeFrame() {
            let start = PreviewClock.now()
            presentedFrame = try surface.upload(frame)
            app.release(frame)
            let duration = PreviewClock.now() - start
            pacer.noteUpload(duration: duration)
            if isDebugLogging {
                debugLog(String(format: "upload %.3f ms", PreviewClock.milliseconds(duration)))
            }
        }
        guard presentedFrame || ticking || needsRedraw else {
            return .running(presentedFrame: false)
        }
        needsRedraw = false

        // With vsync, presenting returns after the refresh. Without it, the
        // loop waits for the refresh itself, on a grid of whole periods, so
        // the small overshoot of each wait does not accumulate.
        var presentTime: UInt64?
        var heldRefresh: UInt64?
        if !pacer.hasVSync, !announcedSoftwarePacing {
            announcedSoftwarePacing = true
            debugLog("presenting does not wait for the display; pacing with a timer")
        }
        if ticking, presentedFrame {
            // A fast app answers long before its frame is due when each frame
            // stays up for more than one refresh, to match the simulated
            // screen. The frame waits, so the app runs no faster.
            let start = PreviewClock.now()
            let refresh = pacer.earliestRefresh(after: lastPresent)
            let time = pacer.presentTime(forRefreshAt: refresh, now: start)
            if time > start { heldRefresh = refresh }
            if wait(until: time, app: app) { return .close }
            if !pacer.hasVSync { presentTime = time }
        }
        if !pacer.hasVSync, presentTime == nil {
            let now = PreviewClock.now()
            let next = pacer.nextPresentTime(after: lastPresent, now: now)
            if next > now { surface.delay(nanoseconds: next - now) }
            presentTime = next
        }
        surface.present()
        let now = presentTime ?? PreviewClock.now()
        if isDebugLogging {
            let returned = PreviewClock.now()
            debugLog(
                String(
                    format: "present at %.3f ms (+%.3f ms)%@", PreviewClock.milliseconds(returned),
                    PreviewClock.milliseconds(now - lastPresent),
                    presentedFrame ? "" : ", same frame"))
        }
        // Only paced presents tell whether vsync waits: presents for input
        // arrive at the pointer's rate.
        if ticking { pacer.notePresented(at: now, heldFor: heldRefresh) }
        lastPresent = now

        if let app = live, app.usesHostClock, app.isAnimating, pacer.shouldTick(now: now) {
            let target = pacer.targetTime(afterPresentAt: now)
            app.send(.tick(PreviewTick(targetTime: target, refreshPeriod: pacer.refreshPeriod)))
            pacer.noteTickSent(target: target, at: now)
            lastTickSent = now
        }
        return .running(presentedFrame: presentedFrame)
    }

    /// Forwards input to the app and notes redraws. Returns whether the user
    /// closed the window or interrupted the tool.
    private func handle(_ events: [SurfaceEvent], app: AppConnection?) -> Bool {
        for event in events {
            switch event {
            case .close: return true
            case .input(let message): app?.send(message)
            case .redraw: needsRedraw = true
            case .appearance(let change):
                if appearance.apply(change) != nil { appearance.send(to: app) }
            }
        }
        return false
    }

    /// Handles events until shortly before `time`, then waits out the rest
    /// precisely. Returns whether the user closed the window.
    private func wait(until time: UInt64, app: AppConnection?) -> Bool {
        while true {
            let now = PreviewClock.now()
            guard time > now else { return false }
            let remaining = time - now
            guard remaining > 2_000_000 else {
                surface.delay(nanoseconds: remaining)
                return false
            }
            // Whole milliseconds, leaving at least one for the precise wait.
            let events = surface.events(
                waitingUpTo: Double((remaining - 1_000_000) / 1_000_000) / 1000)
            if handle(events, app: app) { return true }
        }
    }
}
