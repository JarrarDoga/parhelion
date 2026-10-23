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
        // 12 ms frames, as with an unoptimized framework: 4 refreshes each.
        for _ in 0..<5 { frame(taking: 12_000_000) }
        #expect(pacer.framesPerTick == 4)
        // One fast frame does not change the cadence.
        frame(taking: 1_000_000)
        #expect(pacer.framesPerTick == 4)
        for _ in 0..<FramePacer.roundTripWindow { frame(taking: 1_000_000) }
        #expect(pacer.framesPerTick == 1)
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
        // A slow app still slows down past the screen's rate, and comes back
        // to it, not to every refresh.
        for _ in 0..<3 {
            let target = pacer.targetTime(afterPresentAt: time)
            pacer.noteTickSent(target: target, at: time)
            pacer.noteAnswer(target: target, at: time + 12_000_000)
            time = target
        }
        #expect(pacer.framesPerTick == 4)
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
