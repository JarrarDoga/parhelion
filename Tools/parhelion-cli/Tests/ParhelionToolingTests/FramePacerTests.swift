import Foundation
import Testing

@testable import ParhelionTooling

@Suite("Frame pacing")
struct FramePacerTests {
    @Test("Refresh periods come from SDL's rational rate, then its rounded rate, then 60 Hz")
    func refreshPeriods() {
        #expect(FramePacer.refreshPeriod(numerator: 240, denominator: 1, rate: 240) == 4_166_666)
        #expect(
            FramePacer.refreshPeriod(numerator: 60000, denominator: 1001, rate: 59.94) == 16_683_333
        )
        #expect(FramePacer.refreshPeriod(numerator: 0, denominator: 0, rate: 180) == 5_555_556)
        #expect(FramePacer.refreshPeriod(numerator: 0, denominator: 0, rate: 0) == 16_666_667)
    }

    @Test("A tick targets the refresh after the present, and the deadline leaves room to upload")
    func targets() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        #expect(pacer.targetTime(afterPresentAt: 1_000_000_000) == 1_004_166_667)
        let deadline = pacer.frameDeadline(afterPresentAt: 1_000_000_000)
        #expect(deadline < 1_004_166_667 && deadline > 1_000_000_000)
        pacer.noteUpload(duration: 300_000)
        #expect(pacer.frameDeadline(afterPresentAt: 1_000_000_000) >= deadline)
    }

    @Test("One tick is outstanding at a time, until it is answered or overdue")
    func outstanding() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        #expect(pacer.shouldTick(now: 0))
        pacer.noteTickSent(target: 4_166_667, at: 0)
        #expect(!pacer.shouldTick(now: 4_000_000))
        // An answer to another tick does not count.
        pacer.noteAnswer(target: 99, at: 2_000_000)
        #expect(!pacer.shouldTick(now: 4_000_000))
        pacer.noteAnswer(target: 4_166_667, at: 2_000_000)
        #expect(pacer.shouldTick(now: 4_000_000))
        pacer.noteTickSent(target: 8_333_334, at: 4_166_667)
        #expect(pacer.shouldTick(now: 4_166_667 + 101_000_000), "An overdue tick is replaced")
    }

    @Test("An app that answers within a refresh is shown every refresh")
    func fastApp() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        var time: UInt64 = 0
        for _ in 0..<20 {
            let target = pacer.targetTime(afterPresentAt: time)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + 2_000_000)
            time = target
        }
        #expect(pacer.framesPerTick == 1)
    }

    @Test("A slow app is shown for equal numbers of refreshes, and speeds up only after a while")
    func slowApp() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        var time: UInt64 = 0
        func frame(taking duration: UInt64) {
            let target = pacer.targetTime(afterPresentAt: time)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + duration)
            time = target
        }
        // 12 ms frames, as with an unoptimized framework: 3 refreshes each,
        // 12.5 ms, since the app draws each frame while the last is shown.
        for _ in 0..<5 { frame(taking: 12_000_000) }
        #expect(pacer.framesPerTick == 3)
        // One fast frame does not change the cadence.
        frame(taking: 1_000_000)
        #expect(pacer.framesPerTick == 3)
        for _ in 0..<FramePacer.roundTripWindow { frame(taking: 1_000_000) }
        #expect(pacer.framesPerTick == 1)
    }

    @Test("An answer is shown at its target, on the grid of the last present, or later if late")
    func answerRefresh() {
        let period: UInt64 = 8_333_333
        var pacer = FramePacer(vsyncEnabled: false)
        pacer.setRefreshPeriod(period)
        let last: UInt64 = 1_000_000_000
        // On time: the target, moved onto the last present's grid.
        #expect(
            pacer.refresh(showingAnswerFor: last + period + 3, at: last + 2_000_000, after: last)
                == last + period)
        #expect(
            pacer.refresh(showingAnswerFor: last + 2 * period, at: last, after: last)
                == last + 2 * period)
        // Too late to upload before its refresh: the next one.
        #expect(
            pacer.refresh(showingAnswerFor: last + period, at: last + period - 100_000, after: last)
                == last + 2 * period)
        // Never sooner than the refresh after the last present.
        #expect(
            pacer.refresh(showingAnswerFor: 5, at: last - 5_000_000, after: last) == last + period)
        // The deadline for an answer is shortly before that refresh.
        pacer.noteTickSent(target: last + period, at: last)
        let deadline = pacer.answerDeadline(after: last, now: last)
        #expect(deadline < last + period && deadline > last + period / 2)
        #expect(pacer.answerDeadline(after: last, now: last + period) > last + period)
    }

    @Test("The next tick goes out as an answer arrives, at most one refresh before it is shown")
    func overlappedTicks() {
        let period: UInt64 = 8_333_333
        var pacer = FramePacer(vsyncEnabled: false)
        pacer.setRefreshPeriod(period)
        let shown: UInt64 = 1_000_000_000
        let next = pacer.nextTick(afterShowingAt: shown)
        #expect(next.target == shown + period)
        #expect(next.earliest == shown - period)
        pacer.setMaximumFramesPerSecond(60)
        #expect(pacer.nextTick(afterShowingAt: shown).target == shown + 2 * period)
        #expect(pacer.nextTick(afterShowingAt: shown).earliest == shown - period)
    }

    /// Runs the host's overlapped loop for frames that take `durations` to
    /// draw, and returns the refreshes between the frames shown.
    private func overlap(_ durations: [UInt64], pacer: inout FramePacer) -> [UInt64] {
        let period = pacer.refreshPeriod
        var lastPresent: UInt64 = 1_000_000_000
        var sentAt = lastPresent
        var target = pacer.targetTime(afterPresentAt: lastPresent)
        pacer.noteTickSent(target: target, at: sentAt)
        var gaps: [UInt64] = []
        for duration in durations {
            let arrival = sentAt + duration
            pacer.noteAnswer(target: target, at: arrival)
            let refresh = pacer.refresh(showingAnswerFor: target, at: arrival, after: lastPresent)
            let tick = pacer.nextTick(afterShowingAt: refresh)
            sentAt = max(arrival, tick.earliest)
            target = tick.target
            pacer.noteTickSent(target: target, at: sentAt)
            gaps.append((refresh - lastPresent) / period)
            lastPresent = refresh
        }
        return gaps
    }

    @Test("An app that takes most of a refresh for each frame is shown every refresh")
    func overlappedApp() {
        var pacer = FramePacer(vsyncEnabled: false)
        pacer.setRefreshPeriod(8_333_333)
        // 7.5 ms frames: without the overlap, a frame and its 1 ms upload
        // would not fit in one refresh.
        var gaps = overlap(Array(repeating: 7_500_000, count: 60), pacer: &pacer)
        #expect(gaps.dropFirst().allSatisfy { $0 == 1 })
        #expect(pacer.framesPerTick == 1)
        // A few slow frames, as when rows scroll into view, miss a refresh
        // each, but the frames after them are shown every refresh again.
        let bumpy = (0..<64).map { $0 % 16 == 5 ? UInt64(20_000_000) : 7_000_000 }
        gaps = overlap(bumpy, pacer: &pacer)
        #expect(pacer.framesPerTick == 1)
        #expect(gaps.filter { $0 == 1 }.count >= 56)
        // An app slower than a refresh on average is shown every other one.
        gaps = overlap(Array(repeating: 9_500_000, count: 40), pacer: &pacer)
        #expect(pacer.framesPerTick == 2)
        #expect(gaps.suffix(20).allSatisfy { $0 == 2 })
    }

    @Test("An app a little slower than a refresh on average is shown at most refreshes")
    func slightlySlowApp() {
        var pacer = FramePacer(vsyncEnabled: false)
        pacer.setRefreshPeriod(8_333_333)
        // 8.8 ms frames: each takes from the one refresh the app draws
        // ahead, and about every seventeenth misses its refresh.
        let gaps = overlap(Array(repeating: 8_800_000, count: 120), pacer: &pacer)
        #expect(pacer.framesPerTick == 1)
        #expect(gaps.filter { $0 == 1 }.count >= 105)
    }

    @Test("Presents that return well before a refresh mean vsync is not real")
    func fakeVSync() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        var time: UInt64 = 0
        for _ in 0..<FramePacer.shortIntervalLimit {
            pacer.notePresented(at: time)
            time += 100_000
        }
        #expect(pacer.hasVSync)
        pacer.notePresented(at: time)
        #expect(!pacer.hasVSync)
    }

    @Test("A present that waits now and then does not hide that vsync is not real")
    func fakeVSyncWithSlowFrames() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        var time: UInt64 = 0
        pacer.notePresented(at: time)
        // Two short intervals, then one that waited for a slow frame.
        for index in 0..<(3 * FramePacer.shortIntervalLimit) {
            time += index % 3 == 2 ? 8_000_000 : 100_000
            pacer.notePresented(at: time)
        }
        #expect(!pacer.hasVSync)
    }

    @Test("Held frames that come back long before their refresh mean vsync is not real")
    func fakeVSyncWhileHolding() {
        let period: UInt64 = 4_166_667
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(period)
        pacer.setMaximumFramesPerSecond(120)
        var time: UInt64 = 0
        pacer.notePresented(at: time)
        // Real vsync: each held present returns at its refresh.
        for _ in 0..<10 {
            time = pacer.earliestRefresh(after: time)
            pacer.notePresented(at: time, heldFor: time)
        }
        #expect(pacer.hasVSync)
        // Fake vsync: each returns as soon as it is called, 1.25 periods on.
        for _ in 0...FramePacer.shortIntervalLimit {
            let refresh = pacer.earliestRefresh(after: time)
            time = pacer.presentTime(forRefreshAt: refresh, now: time)
            pacer.notePresented(at: time, heldFor: refresh)
        }
        #expect(!pacer.hasVSync)
    }

    @Test("Real vsync survives a few early presents after an idle period")
    func realVSync() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        var time: UInt64 = 0
        for index in 0..<100 {
            pacer.notePresented(at: time)
            // Two queued buffers return at once every so often.
            time += index % 20 < 2 ? 50_000 : 4_166_667
        }
        #expect(pacer.hasVSync)
    }

    @Test("Without vsync, presents fall on a grid of whole periods")
    func softwarePacing() {
        let pacer = FramePacer(vsyncEnabled: false)
        #expect(pacer.nextPresentTime(after: 100, now: 200) == 100 + 16_666_667)
        #expect(pacer.nextPresentTime(after: 100, now: 50_000_000) == 50_000_000)
    }

    @Test("Each frame stays up long enough to keep the app at the screen's rate or below")
    func screenRates() {
        func floor(display hertz: Float, screen rate: Int?) -> Int {
            FramePacer.minimumFramesPerTick(
                refreshPeriod: FramePacer.refreshPeriod(numerator: 0, denominator: 0, rate: hertz),
                maximumFramesPerSecond: rate)
        }
        #expect(floor(display: 240, screen: 120) == 2)
        #expect(floor(display: 240, screen: 60) == 4)
        #expect(floor(display: 120, screen: 120) == 1)
        #expect(floor(display: 119.88, screen: 120) == 1)
        #expect(floor(display: 120.5, screen: 120) == 1)
        #expect(floor(display: 60, screen: 120) == 1)
        #expect(floor(display: 144, screen: 120) == 2, "72 Hz, not faster than the screen")
        #expect(floor(display: 240, screen: nil) == 1)
    }

    @Test("A fast app simulating a 120 Hz screen on a 240 Hz display is shown every other refresh")
    func cappedFastApp() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        pacer.setMaximumFramesPerSecond(120)
        #expect(pacer.framesPerTick == 2)
        var time: UInt64 = 0
        for _ in 0..<20 {
            let target = pacer.targetTime(afterPresentAt: time)
            #expect(target == time + 8_333_334)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + 1_000_000)
            time = target
        }
        #expect(pacer.framesPerTick == 2)
        // A slow app still slows down past the screen's rate, once more than
        // a few frames are slow, and comes back to it, not to every refresh.
        for _ in 0...FramePacer.toleratedSlowFrames {
            let target = pacer.targetTime(afterPresentAt: time)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + 12_000_000)
            time = target
        }
        #expect(pacer.framesPerTick == 3)
        for _ in 0..<FramePacer.roundTripWindow {
            let target = pacer.targetTime(afterPresentAt: time)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + 1_000_000)
            time = target
        }
        #expect(pacer.framesPerTick == 2)
        pacer.reset()
        #expect(pacer.framesPerTick == 2, "A new app keeps the screen's rate")
        pacer.setRefreshPeriod(8_333_333)
        #expect(pacer.framesPerTick == 1, "A 120 Hz display shows every refresh")
        pacer.setMaximumFramesPerSecond(60)
        #expect(pacer.framesPerTick == 2)
    }

    @Test("An early frame is held until the screen's rate allows it")
    func presentTimes() {
        let period: UInt64 = 4_166_667
        var vsync = FramePacer(vsyncEnabled: true)
        vsync.setRefreshPeriod(period)
        #expect(vsync.earliestRefresh(after: 0) == period)
        vsync.setMaximumFramesPerSecond(120)
        #expect(vsync.earliestRefresh(after: 0) == 2 * period)
        let refresh: UInt64 = 1_000_000_000
        // Presenting waits for the next refresh, so a quarter period after
        // the one before is enough.
        #expect(
            vsync.presentTime(forRefreshAt: refresh, now: 990_000_000)
                == refresh - period + period / 4)
        #expect(vsync.presentTime(forRefreshAt: refresh, now: 999_000_000) == 999_000_000)
        var timer = FramePacer(vsyncEnabled: false)
        timer.setRefreshPeriod(period)
        #expect(timer.presentTime(forRefreshAt: refresh, now: 990_000_000) == refresh)
        #expect(timer.presentTime(forRefreshAt: refresh, now: 1_002_000_000) == 1_002_000_000)
    }

    @Test("Moving to another display starts over at one refresh per frame")
    func displayChange() {
        var pacer = FramePacer(vsyncEnabled: true)
        pacer.setRefreshPeriod(4_166_667)
        pacer.noteTickSent(target: 1, at: 0)
        pacer.noteAnswer(target: 1, at: 12_000_000)
        #expect(pacer.framesPerTick > 1)
        pacer.setRefreshPeriod(5_555_556)
        #expect(pacer.framesPerTick == 1 && pacer.refreshPeriod == 5_555_556)
    }
}
