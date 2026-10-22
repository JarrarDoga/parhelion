import CSDL3
import Foundation
import ParhelionPreview
import ParhelionTooling

/// The window host's main loop: it forwards input to the app, shows the
/// app's newest frame, and, while the app animates, paces it to the
/// display.
///
/// Each ``step(app:idleTimeout:)`` is one pass. While the app animates and
/// draws for the host's clock, a pass waits for the app's answer to the last
/// tick until shortly before the next refresh, uploads it, presents (which
/// waits for the refresh), and sends the next tick. Otherwise a pass blocks
/// until input, a frame, or `idleTimeout`, so an idle preview uses no CPU.
/// ``FramePacer`` holds the timing rules.
final class FrameLoop {
    private let window: WindowHost
    private var pacer: FramePacer
    /// The app the pacer's timing belongs to.
    private var appIdentity: ObjectIdentifier?
    private var lastPresent: UInt64 = 0
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

    init(window: WindowHost) {
        self.window = window
        pacer = FramePacer(vsyncEnabled: window.hasVSync)
        pacer.setRefreshPeriod(window.refreshPeriod)
    }

    /// Runs one pass of the loop for `app`, which may change between passes
    /// when hot reload starts a new build.
    func step(app: AppConnection?, idleTimeout: Double) throws -> Step {
        if appIdentity != app.map(ObjectIdentifier.init) {
            appIdentity = app.map(ObjectIdentifier.init)
            pacer.reset()
        }
        pacer.setRefreshPeriod(window.refreshPeriod)
        let ticking =
            app.map { $0.usesHostClock && ($0.isAnimating || pacer.outstandingTarget != nil) }
            ?? false

        var events: [WindowHost.Event] = []
        if let app, ticking {
            // Wait for the app's answer until the frame deadline, handling
            // input as it arrives. The reader thread wakes the wait.
            let deadline = pacer.frameDeadline(afterPresentAt: lastPresent)
            while !app.hasNews, !app.isDisconnected {
                let now = PreviewClock.now()
                guard deadline > now + 1_000_000 else { break }
                // Whole milliseconds, rounded down, so the wait ends before
                // the deadline.
                events += window.events(waitingUpTo: Double((deadline - now) / 1_000_000) / 1000)
                if events.contains(where: { if case .close = $0 { true } else { false } }) { break }
            }
            events += window.events(waitingUpTo: 0)
        } else {
            events = window.events(waitingUpTo: idleTimeout)
        }
        for event in events {
            switch event {
            case .close: return .close
            case .input(let message): app?.send(message)
            case .redraw: needsRedraw = true
            }
        }

        if let answer = app?.takeAnswer() {
            pacer.noteAnswer(target: answer.target, at: answer.arrival)
        }
        var presentedFrame = false
        if let app, let frame = app.takeFrame() {
            let start = PreviewClock.now()
            presentedFrame = try window.upload(frame)
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
        if !pacer.hasVSync {
            if !announcedSoftwarePacing {
                announcedSoftwarePacing = true
                debugLog("presenting does not wait for the display; pacing with a timer")
            }
            let now = PreviewClock.now()
            let next = pacer.nextPresentTime(after: lastPresent, now: now)
            if next > now { SDL_DelayPrecise(next - now) }
            presentTime = next
        }
        window.present()
        let now = presentTime ?? PreviewClock.now()
        if isDebugLogging {
            let returned = PreviewClock.now()
            debugLog(
                String(
                    format: "present at %.3f ms (+%.3f ms)%@", PreviewClock.milliseconds(returned),
                    PreviewClock.milliseconds(now - lastPresent),
                    presentedFrame ? "" : ", same frame"))
        }
        pacer.notePresented(at: now)
        lastPresent = now

        if let app, app.usesHostClock, app.isAnimating, pacer.shouldTick(now: now) {
            let target = pacer.targetTime(afterPresentAt: now)
            app.send(.tick(PreviewTick(targetTime: target, refreshPeriod: pacer.refreshPeriod)))
            pacer.noteTickSent(target: target, at: now)
        }
        return .running(presentedFrame: presentedFrame)
    }
}
