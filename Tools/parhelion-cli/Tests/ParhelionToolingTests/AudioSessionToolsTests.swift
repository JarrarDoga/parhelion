import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("The audio_interruption and audio_route_change tools")
struct AudioSessionToolsTests {
    private func registry() -> AgentToolRegistry {
        let registry = AgentToolRegistry()
        registry.register(AudioInterruptionTool())
        registry.register(AudioRouteChangeTool())
        return registry
    }

    private func command(_ name: String, _ arguments: [String: Any]) -> PreviewCommand? {
        guard case .command(let command)? = registry().call(name, MCPArguments(arguments)) else {
            return nil
        }
        return command
    }

    @Test("Both are listed")
    func listing() {
        #expect(registry().definitions.map(\.name) == ["audio_interruption", "audio_route_change"])
    }

    @Test("A beginning interruption carries its reason")
    func began() {
        #expect(
            command("audio_interruption", ["type": "began", "reason": "appWasSuspended"])
                == .audioInterruption(began: true, shouldResume: false, reason: "appWasSuspended"))
        #expect(
            command("audio_interruption", ["type": "began"])
                == .audioInterruption(began: true, shouldResume: false, reason: nil))
    }

    @Test("An ended interruption carries the resume option")
    func ended() {
        #expect(
            command("audio_interruption", ["type": "ended", "should_resume": true])
                == .audioInterruption(began: false, shouldResume: true, reason: nil))
        #expect(
            command("audio_interruption", ["type": "ended"])
                == .audioInterruption(began: false, shouldResume: false, reason: nil))
    }

    @Test("An interruption without a valid type is an error")
    func missingType() {
        for arguments in [[:], ["type": "paused"]] as [[String: Any]] {
            guard
                case .result(let result)? = registry().call(
                    "audio_interruption", MCPArguments(arguments))
            else {
                Issue.record("expected an error result")
                continue
            }
            #expect(result.isError)
        }
    }

    @Test("A route change defaults to headphones coming out")
    func routeChange() {
        #expect(
            command("audio_route_change", [:])
                == .audioRouteChange(reason: "oldDeviceUnavailable", device: "headphones"))
        #expect(
            command(
                "audio_route_change", ["reason": "newDeviceAvailable", "device": "bluetoothA2DP"])
                == .audioRouteChange(reason: "newDeviceAvailable", device: "bluetoothA2DP"))
    }

    @Test("The commands survive the wire")
    func codable() throws {
        let commands: [PreviewCommand] = [
            .audioInterruption(began: true, shouldResume: false, reason: "default"),
            .audioRouteChange(reason: "oldDeviceUnavailable", device: "headphones"),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            #expect(try JSONDecoder().decode(PreviewCommand.self, from: data) == command)
        }
    }
}
