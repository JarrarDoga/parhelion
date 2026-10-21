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
    var pressedNodeID: NodeID?
    var isAnimating: Bool
}

extension ViewHost {
    /// Runs a tool's command and describes the result.
    func execute(_ command: PreviewCommand) -> PreviewReply {
        func reply(_ ok: Bool, _ message: String, png: Data? = nil) -> PreviewReply {
            PreviewReply(
                ok: ok, message: message, png: png, revision: revision, isAnimating: isAnimating)
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

            case .typeText(let text):
                guard let focused = focusedNodeID else {
                    return reply(false, "No text field is focused. Focus one first.")
                }
                typeText(text)
                return reply(true, "Typed \(text.count) characters into \(focused).")

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

    /// Moves a press from one point to another in 60 steps per second of
    /// `duration`, advancing the clock as it goes, then releases it.
    func drag(from start: CGPoint, to end: CGPoint, duration: Double) {
        let duration = min(max(duration, 0.02), 5)
        let steps = max(Int(duration * 60), 2)
        pointerDown(at: start)
        for step in 1...steps {
            advanceTime(by: duration / Double(steps))
            let t = CGFloat(step) / CGFloat(steps)
            pointerMoved(
                to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        pointerUp(at: end)
    }

    private func inspectionOutline() -> String {
        var header = "revision \(revision)"
        if let focusedNodeID { header += " · editing \(focusedNodeID) at character \(caretOffset)" }
        if isAnimating { header += " · animating" }
        return header + "\n" + root.outline(includeIDs: true, includeFrames: true)
    }

    private func inspectionJSON() throws -> String {
        let report = InspectionReport(
            root: root,
            revision: revision,
            focusedNodeID: focusedNodeID,
            caretOffset: focusedNodeID == nil ? nil : caretOffset,
            pressedNodeID: pressedNodeID,
            isAnimating: isAnimating
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
        }
    }
}
