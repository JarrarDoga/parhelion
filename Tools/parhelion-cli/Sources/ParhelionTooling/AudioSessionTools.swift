import ParhelionPreview

// The tools that make iOS's audio events happen in the preview: a call or Siri
// taking the audio, and headphones coming out. They plug in through
// ``AgentToolRegistry``, and the app posts `AVAudioSession`'s notifications, so
// an app's handlers run as they would on a phone. See
// docs/adr/0018-audio-session-events.md.

/// The `audio_interruption` tool: an audio interruption begins or ends.
public struct AudioInterruptionTool: AgentTool {
    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "audio_interruption",
            title: "Begin or end an audio interruption",
            description: """
                Posts AVAudioSession.interruptionNotification to the app, as iOS does when a \
                call, Siri, or an alarm takes the audio. With type "began", the app should \
                pause; the audio session becomes inactive and `reason` (default, \
                appWasSuspended, builtInMicMuted, or routeDisconnected) goes with it. With \
                type "ended", the notification carries the shouldResume option when \
                `should_resume` is true, and the app may resume. Only an app that imports \
                AVFAudio and observes the notification reacts. The screen is read again \
                afterwards.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "type": {"type": "string", "enum": ["began", "ended"]},
                  "should_resume": {"type": "boolean", "default": false},
                  "reason": {"type": "string", "enum": [
                    "default", "appWasSuspended", "builtInMicMuted", "routeDisconnected"]}},
                 "required": ["type"]}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        switch arguments.string("type") {
        case "began":
            return .command(
                .audioInterruption(
                    began: true, shouldResume: false, reason: arguments.string("reason")))
        case "ended":
            return .command(
                .audioInterruption(
                    began: false, shouldResume: arguments.bool("should_resume") ?? false,
                    reason: nil))
        default:
            return .result(.text("audio_interruption needs type: began or ended.", isError: true))
        }
    }
}

/// The `audio_route_change` tool: the audio route changes.
public struct AudioRouteChangeTool: AgentTool {
    public init() {}

    public var definition: MCPTool {
        MCPTool(
            name: "audio_route_change",
            title: "Change the audio route",
            description: """
                Posts AVAudioSession.routeChangeNotification to the app, as iOS does when \
                headphones are unplugged or paired. The default reason, oldDeviceUnavailable, \
                takes `device` away: the notification's previous route has it, and the session's \
                current route is the speaker, so an app that pauses when headphones come out \
                pauses. With newDeviceAvailable, `device` comes in. Reasons: unknown, \
                newDeviceAvailable, oldDeviceUnavailable, categoryChange, override, \
                wakeFromSleep, noSuitableRouteForCategory, routeConfigurationChange. Devices: \
                headphones (default), bluetoothA2DP, airPlay, usbAudio, carAudio. Only an app \
                that imports AVFAudio and observes the notification reacts.
                """,
            inputSchema: #"""
                {"type": "object", "properties": {
                  "reason": {"type": "string", "default": "oldDeviceUnavailable"},
                  "device": {"type": "string", "default": "headphones"}}}
                """#
        )
    }

    public func call(_ arguments: MCPArguments) -> AgentToolOutcome {
        .command(
            .audioRouteChange(
                reason: arguments.string("reason") ?? "oldDeviceUnavailable",
                device: arguments.string("device") ?? "headphones"))
    }
}
