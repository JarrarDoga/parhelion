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
