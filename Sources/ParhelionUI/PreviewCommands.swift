import ParhelionPreview

#if canImport(Foundation)
import Foundation
#endif

/// The state of the screen that tools see alongside the tree.
struct InspectionReport: Codable {
    var root: ViewNode
    var revision: Int
    var focusedNodeID: NodeID?
    var caretOffset: Int?
    /// The selected characters of the focused field, as `[start, end]`.
    var selectedRange: [Int]?
    var pressedNodeID: NodeID?
    var isAnimating: Bool
    var pendingTasks: Int
}

extension ViewHost {
    /// Runs a tool's command and describes the result.
    func execute(_ command: PreviewCommand) -> PreviewReply {
        // A command sees, and acts on, the views on screen now.
        update()
        func reply(_ ok: Bool, _ message: String, png: Data? = nil) -> PreviewReply {
            PreviewReply(
                ok: ok, message: message, png: png, revision: revision, isAnimating: isAnimating,
                pendingTasks: pendingTaskCount, nextWake: secondsUntilNextWake)
        }
        do {
            switch command {
            case .inspect(let json):
                return reply(true, json ? try inspectionJSON() : inspectionOutline())

            case .screenshot(let scale):
                guard scale > 0, scale <= 4 else {
                    return reply(false, "The scale must be in 0...4.")
                }
                // Like a screenshot taken in the Simulator: the status bar and
                // the home indicator, but square corners and no Dynamic Island,
                // so every point of the image is a point on the screen.
                let frame = render(scale: scale, chrome: .systemBars)
                return reply(
                    true,
                    "\(frame.pixelWidth) × \(frame.pixelHeight) pixels at scale \(formatPoints(CGFloat(scale))).",
                    png: frame.pngData()
                )

            case .tapNode(let id):
                try tap(NodeID(id))
                return reply(true, "Tapped \(id).")

            case .tapButton(let label):
                try tapButton(labeled: label)
                return reply(true, "Tapped the button labeled \"\(label)\".")

            case .tapAccessibilityIdentifier(let identifier):
                try tap(accessibilityIdentifier: identifier)
                return reply(true, "Tapped the view identified \"\(identifier)\".")

            case .tapPoint(let x, let y):
                let point = CGPoint(x: x, y: y)
                pointerDown(at: point)
                if let tapped = pointerUp(at: point) {
                    return reply(
                        true,
                        "Tapped \(tapped) at (\(formatPoints(point.x)), \(formatPoints(point.y))).")
                }
                return reply(
                    false,
                    "Nothing that responds to taps is at (\(formatPoints(point.x)), \(formatPoints(point.y)))."
                )

            case .focus(let id):
                try focus(id.map { NodeID($0) })
                return reply(true, id.map { "Focused \($0)." } ?? "Ended editing.")

            case .focusAccessibilityIdentifier(let identifier):
                try focus(accessibilityIdentifier: identifier)
                return reply(true, "Focused the text field identified \"\(identifier)\".")

            case .typeText(let text):
                guard let focused = focusedNodeID else {
                    return reply(false, "No text field is focused. Focus one first.")
                }
                typeText(text)
                return reply(true, "Typed \(text.count) characters into \(focused).")

            case .setPasteboard(let text):
                copyToPasteboard(text)
                return reply(
                    true,
                    "Put \(text.count) character\(text.count == 1 ? "" : "s") on the clipboard.")

            case .pressKey(let name):
                guard let key = Key(rawValue: name) else {
                    let names = Key.allCases.map(\.rawValue).joined(separator: ", ")
                    return reply(false, "Unknown key \"\(name)\". Use one of: \(names).")
                }
                press(key)
                return reply(true, "Pressed \(name).")

            case .scroll(let dx, let dy, let x, let y):
                let scrolled = scroll(by: CGSize(width: dx, height: dy), at: CGPoint(x: x, y: y))
                return reply(
                    scrolled, scrolled ? "Scrolled." : "Nothing at that point can scroll that way.")

            case .scrollTo(let id, let x, let y):
                try scroll(NodeID(id), to: CGPoint(x: x, y: y))
                let offset = scrollOffset(of: NodeID(id)) ?? .zero
                return reply(
                    true,
                    "Scrolled \(id) to (\(formatPoints(offset.x)), \(formatPoints(offset.y))).")

            case .scrollToAccessibilityIdentifier(let identifier, let x, let y):
                try scroll(accessibilityIdentifier: identifier, to: CGPoint(x: x, y: y))
                return reply(true, "Scrolled the view identified \"\(identifier)\".")

            case .setAppearance(let schemeName, let sizeName):
                if let schemeName {
                    guard let scheme = ColorScheme(name: schemeName) else {
                        return reply(
                            false, "Unknown color scheme \"\(schemeName)\". Use light or dark.")
                    }
                    colorScheme = scheme
                }
                if let sizeName {
                    guard let size = DynamicTypeSize(name: sizeName) else {
                        let names = DynamicTypeSize.allCases.map(\.name).joined(separator: ", ")
                        return reply(
                            false,
                            "Unknown Dynamic Type size \"\(sizeName)\". Use one of: \(names).")
                    }
                    dynamicTypeSize = size
                }
                return reply(true, appearanceDescription)

            case .setReduceMotion(let on):
                reduceMotion = on
                return reply(true, "Reduce Motion is \(on ? "on" : "off").")

            case .sensoryFeedback(let clear):
                let description = sensoryFeedbackDescription
                if clear { clearSensoryFeedback() }
                return reply(true, description)

            case .setScenePhase(let name):
                guard let phase = ScenePhase(name: name) else {
                    return reply(
                        false,
                        "Unknown scene phase \"\(name)\". Use active, inactive, or background.")
                }
                scenePhase = phase
                return reply(true, "The scene is \(phase.name).")

            case .advanceTime(let seconds):
                guard hasManualClock else {
                    let key = previewManualClockEnvironmentKey
                    return reply(
                        false, "The app's clock is real. Start it with \(key)=1 to advance it.")
                }
                guard seconds.isFinite, seconds >= 0, seconds <= Self.longestAdvance else {
                    let longest = Int(Self.longestAdvance)
                    return reply(false, "The time to advance must be in 0...\(longest) seconds.")
                }
                advanceClock(by: seconds)
                return reply(true, "Advanced the clock by \(formatSeconds(seconds)).")

            case .replay(let flow, let updatingCheckpoints):
                let report = replay(flow, updatingCheckpoints: updatingCheckpoints)
                var result = reply(report.passed, report.summary)
                result.flowReport = report
                return result

            case .drag(let fromX, let fromY, let toX, let toY, let duration):
                drag(
                    from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY),
                    duration: duration)
                return reply(
                    true, isAnimating ? "Dragged; the content is still moving." : "Dragged.")
            }
        } catch {
            return reply(false, describe(error))
        }
    }

    /// The most one `advanceTime` command moves the clock, in seconds.
    static let longestAdvance: TimeInterval = 3600

    /// The simulated device's settings, as a reply states them.
    var appearanceDescription: String {
        "The device is set to \(colorScheme.name) at Dynamic Type size \(dynamicTypeSize.name)"
            + (reduceMotion ? " with Reduce Motion on." : ".")
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        "\(formatPoints(CGFloat(seconds))) s"
    }

    private func inspectionOutline() -> String {
        var header = "revision \(revision)"
        if let focusedNodeID { header += " · editing \(focusedNodeID) at character \(caretOffset)" }
        if let range = selectedRange {
            header += " · selected characters \(range.lowerBound)..<\(range.upperBound)"
        }
        if isAnimating { header += " · animating" }
        if pendingTaskCount > 0 {
            header += " · \(pendingTaskCount) task\(pendingTaskCount == 1 ? "" : "s") running"
        }
        return header + "\n" + root.outline(includeIDs: true, includeFrames: true)
    }

    private func inspectionJSON() throws -> String {
        let report = InspectionReport(
            root: root,
            revision: revision,
            focusedNodeID: focusedNodeID,
            caretOffset: focusedNodeID == nil ? nil : caretOffset,
            selectedRange: selectedRange.map { [$0.lowerBound, $0.upperBound] },
            pressedNodeID: pressedNodeID,
            isAnimating: isAnimating,
            pendingTasks: pendingTaskCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func describe(_ error: any Error) -> String {
        guard let error = error as? InteractionError else { return "\(error)" }
        switch error {
        case .nodeNotFound(let id): return "No node has the identifier \(id)."
        case .notTappable(let id): return "\(id) does not respond to taps."
        case .noButton(let label): return "No button is labeled \"\(label)\"."
        case .ambiguousButton(let label, let matches):
            return
                "Several buttons are labeled \"\(label)\": \(matches.map(\.rawValue).joined(separator: ", ")). Tap one by identifier."
        case .nothingTappable(let point):
            return
                "Nothing that responds to taps is at (\(formatPoints(point.x)), \(formatPoints(point.y)))."
        case .notScrollable(let id): return "\(id) is not a scroll view."
        case .notEditable(let id): return "\(id) is not a text field."
        case .covered(let id):
            return "\(id) is behind a sheet or an alert. Use the sheet or alert first."
        case .noAccessibilityIdentifier(let identifier):
            return "No view on screen has the accessibility identifier \"\(identifier)\"."
        case .ambiguousAccessibilityIdentifier(let identifier, let matches):
            return
                "Several views have the accessibility identifier \"\(identifier)\": \(matches.map(\.rawValue).joined(separator: ", ")). Use id for one of them."
        }
    }
}
