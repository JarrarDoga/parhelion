#if canImport(Glibc)
import Foundation
import Glibc
import Testing

@testable import ParhelionPreview

/// Runs the built `Library` example, whose `task` sleeps 300 ms before it
/// shows its books, as a window host would, and checks how it keeps time.
/// The test runner owns its own `main`, so only a separate process can run on
/// the manual clock.
@Suite("Manual clock in an app process", .serialized)
struct ManualClockProcessTests {
    /// The built example, or `nil` when it is not next to the test products.
    static var libraryExecutable: String? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let products = [
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            root.appendingPathComponent(".build/debug"),
        ]
        return products.map { $0.appendingPathComponent("Library").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// An app process and the channel to it.
    final class Session {
        let process = Process()
        let channel: PreviewChannel
        let hello: PreviewHello
        private var nextID = 1

        init(
            executable: String, manualClock: Bool, environment extra: [String: String] = [:]
        ) throws {
            let path = NSTemporaryDirectory() + "parhelion-clock-\(UUID().uuidString).sock"
            let listener = try PreviewListener(path: path)
            process.executableURL = URL(fileURLWithPath: executable)
            var environment = ProcessInfo.processInfo.environment
            environment[previewSocketEnvironmentKey] = path
            environment[previewManualClockEnvironmentKey] = manualClock ? "1" : nil
            environment.merge(extra) { $1 }
            process.environment = environment
            try process.run()
            guard let channel = try listener.accept(timeout: 30) else {
                process.terminate()
                throw PreviewChannel.ChannelError.closed
            }
            self.channel = channel
            guard case .hello(let hello) = try channel.receiveAppMessage(timeout: 30) else {
                process.terminate()
                throw PreviewChannel.ChannelError.closed
            }
            self.hello = hello
            let wanted = hello.capabilities?.filter { $0 == PreviewCapability.manualClock } ?? []
            try channel.send(.welcome(PreviewWelcome(capabilities: wanted)))
        }

        /// Sends a command and waits for its reply, skipping frames.
        func request(_ command: PreviewCommand) throws -> PreviewReply {
            let id = nextID
            nextID += 1
            try channel.send(.command(id: id, command))
            while true {
                guard let message = try channel.receiveAppMessage(timeout: 30) else {
                    throw PreviewChannel.ChannelError.closed
                }
                if case .reply(let replyID, let reply) = message, replyID == id { return reply }
            }
        }

        func finish() {
            try? channel.send(.close)
            // The app may be sending a frame; reading lets it finish and exit.
            let deadline = Date(timeIntervalSinceNow: 5)
            while process.isRunning, Date() < deadline {
                _ = try? channel.receiveAppMessage(timeout: 0.05)
            }
            // SIGTERM can stay blocked in a child of the test runner.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
    }

    @Test("advanceTime wakes a task that sleeps without waiting in real time")
    func advanceWakesSleepingTask() throws {
        guard let executable = Self.libraryExecutable else {
            Issue.record("The Library example is not built next to the tests.")
            return
        }
        let session = try Session(executable: executable, manualClock: true)
        defer { session.finish() }
        #expect(session.hello.capabilities?.contains(PreviewCapability.manualClock) == true)

        // The task starts at once and then sleeps 300 ms of the app's time.
        let started = try session.request(.inspect(json: false))
        #expect(started.pendingTasks == 1)
        // Real time does not wake it.
        Thread.sleep(forTimeInterval: 0.6)
        let held = try session.request(.inspect(json: false))
        #expect(held.pendingTasks == 1)
        #expect(held.message.contains("Loading"))
        let wake = try #require(held.nextWake)
        #expect(wake > 0.29 && wake <= 0.301)

        // Ten seconds of the app's time pass in well under one second of ours.
        let start = Date()
        let advanced = try session.request(.advanceTime(seconds: 10))
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(advanced.ok)
        #expect(advanced.pendingTasks == 0)
        #expect(advanced.nextWake == nil)
        let finished = try session.request(.inspect(json: false))
        #expect(finished.message.contains("Piranesi"))
    }

    @Test("A sleep that is not yet due keeps waiting")
    func partialAdvance() throws {
        guard let executable = Self.libraryExecutable else {
            Issue.record("The Library example is not built next to the tests.")
            return
        }
        let session = try Session(executable: executable, manualClock: true)
        defer { session.finish() }
        _ = try session.request(.inspect(json: false))
        let early = try session.request(.advanceTime(seconds: 0.2))
        #expect(early.pendingTasks == 1)
        let wake = try #require(early.nextWake)
        #expect(wake > 0.09 && wake <= 0.101)
        let late = try session.request(.advanceTime(seconds: 0.1))
        #expect(late.pendingTasks == 0)
    }

    @Test("An app on the real clock refuses advanceTime")
    func realClockRefuses() throws {
        guard let executable = Self.libraryExecutable else {
            Issue.record("The Library example is not built next to the tests.")
            return
        }
        let session = try Session(executable: executable, manualClock: false)
        defer { session.finish() }
        #expect(session.hello.capabilities?.contains(PreviewCapability.manualClock) == false)
        let reply = try session.request(.advanceTime(seconds: 1))
        #expect(!reply.ok)
        #expect(reply.message.contains(previewManualClockEnvironmentKey))
    }
}
#endif
