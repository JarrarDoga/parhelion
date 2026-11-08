import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// `confirmationDialog`. On iOS 26 and later, a confirmation dialog is not a
// sheet of buttons at the bottom of the screen: it is a popover above the
// view it is attached to, with an arrow pointing at the view, as an iPhone
// on iOS 27 shows it. The kinds register themselves through the extension
// seam (NodeBehavior.swift), so no shared file has a `case` for them.
//
// The tree of a presented dialog:
//
//     ConfirmationDialog        a presentation over the screen; a tap outside
//     │                         the panel runs the cancel action and closes it
//     └─ ConfirmationDialogPanel  the bubble and its arrow
//        ├─ Text                the title, when it is visible
//        ├─ …                   the message, if any
//        └─ Button …            each action but the cancel action, a capsule

extension View {
    /// Presents a confirmation dialog while `isPresented` is `true`. Every
    /// action dismisses the dialog after it runs.
    ///
    /// The dialog is a popover above this view, with an arrow pointing at
    /// it. Each action is a capsule as wide as the popover; a destructive
    /// one is red. A ``ButtonRole/cancel`` action is not shown: tapping
    /// outside the popover runs it.
    public func confirmationDialog<Actions: View>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        ConfirmationDialogView(
            content: self, title: String(title), titleVisibility: titleVisibility,
            isPresented: isPresented, actions: isPresented.wrappedValue ? actions() : nil,
            message: EmptyView?.none)
    }

    /// Presents a confirmation dialog with a message while `isPresented` is
    /// `true`.
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        let shown = isPresented.wrappedValue
        return ConfirmationDialogView(
            content: self, title: String(title), titleVisibility: titleVisibility,
            isPresented: isPresented, actions: shown ? actions() : nil,
            message: shown ? message() : nil)
    }

    /// Presents a confirmation dialog about some data while `isPresented` is
    /// `true` and the data is not `nil`.
    public func confirmationDialog<Actions: View, T>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: (T) -> Actions
    ) -> some View {
        let data = isPresented.wrappedValue ? data : nil
        return ConfirmationDialogView(
            content: self, title: String(title), titleVisibility: titleVisibility,
            isPresented: isPresented, actions: data.map(actions), message: EmptyView?.none)
    }

    /// Presents a confirmation dialog with a message about some data while
    /// `isPresented` is `true` and the data is not `nil`.
    public func confirmationDialog<Actions: View, Message: View, T>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: (T) -> Actions,
        @ViewBuilder message: (T) -> Message
    ) -> some View {
        let data = isPresented.wrappedValue ? data : nil
        return ConfirmationDialogView(
            content: self, title: String(title), titleVisibility: titleVisibility,
            isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }
}

/// A view that presents a confirmation dialog. `actions` is `nil` while the
/// dialog is not presented.
struct ConfirmationDialogView<Content: View, Actions: View, Message: View>: View {
    typealias Body = Never

    let content: Content
    let title: String
    let titleVisibility: Visibility
    let isPresented: Binding<Bool>
    let actions: Actions?
    let message: Message?

    var body: Never {
        fatalError("ConfirmationDialogView is a primitive view and has no body.")
    }
}

extension ConfirmationDialogView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard let actions else { return nodes }
        ConfirmationDialogLayout.registerBehaviors()
        let ownPath = path.appending("confirmationDialog")
        let id = ownPath.id
        let isPresented = isPresented
        let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false }
        var environment = evaluator.environment.presenting(dismiss: dismiss)
        // The actions draw as the dialog's capsules, whatever style is set
        // around it.
        environment.buttonContext = .standard
        environment.buttonStyle = .builtIn(.automatic)
        environment.labelStyle = .builtIn(.automatic)
        environment.isInSheet = false
        let anchor = nodes.first?.id
        let title = titleVisibility == .visible ? title : nil
        let message = message
        evaluator.registerPresentation(
            Presentation(id: id, dismiss: dismiss, onDismiss: nil) { evaluator in
                evaluator.withEnvironment({ $0 = evaluator.startingPresentation(in: environment) })
                {
                    var buttons: [ViewNode] = []
                    var cancel: (@MainActor () -> Void)?
                    for node in evaluator.evaluate(actions, at: ownPath.appending("actions"))
                    where node.kind == "Button" {
                        if node.attributes["role"] == "cancel" {
                            cancel = evaluator.actions[node.id]
                        } else {
                            evaluator.appendToAction(for: node.id, dismiss)
                            buttons.append(node)
                        }
                    }
                    // A tap outside the panel cancels.
                    evaluator.registerAction(
                        {
                            cancel?()
                            dismiss()
                        }, for: id)
                    var children: [ViewNode] = []
                    if let title {
                        var attributes = ["text": title]
                        Font.body.resolved(
                            dynamicTypeSize: evaluator.environment.dynamicTypeSize
                        ).record(in: &attributes)
                        children.append(
                            ViewNode(
                                id: ownPath.appending("title").id, kind: "Text",
                                attributes: attributes))
                    }
                    if let message {
                        // Assumed: the message is secondary text, as in an
                        // alert.
                        let messageNodes = evaluator.withEnvironment({
                            $0.font = $0.font ?? .subheadline
                        }) {
                            evaluator.evaluate(message, at: ownPath.appending("message"))
                        }
                        children += messageNodes.map { node in
                            var node = node
                            node.attributes["foregroundStyle"] =
                                node.attributes["foregroundStyle"] ?? "secondary"
                            node.attributes["role"] = "message"
                            return node
                        }
                    }
                    let panel = ViewNode(
                        id: id.appending("panel"), kind: "ConfirmationDialogPanel",
                        children: children + buttons)
                    var attributes = ["label": "Dismiss"]
                    if let anchor { attributes["anchor"] = anchor.rawValue }
                    return ViewNode(
                        id: id, kind: "ConfirmationDialog", attributes: attributes,
                        children: [panel])
                }
            })
        return nodes
    }
}

// MARK: - Layout

/// The measurements of a confirmation dialog's popover, from an iPhone on
/// iOS 27 at 3 pixels per point.
enum ConfirmationDialogLayout {
    /// The space between the panel's sides and bottom and its content.
    static let padding: CGFloat = 16
    /// The space above the first line of text.
    static let topPadding: CGFloat = 20
    /// The space between the text and the first action.
    static let textSpacing: CGFloat = 18
    /// Assumed: the space between the title and the message.
    static let messageSpacing: CGFloat = 4
    /// Assumed: the space between two actions.
    static let buttonSpacing: CGFloat = 8
    /// The height of an action's capsule.
    static let buttonHeight: CGFloat = 48
    /// The space between an action's label and the ends of its capsule.
    static let buttonPadding: CGFloat = 24
    /// The panel's corner radius.
    static let cornerRadius: CGFloat = 32
    /// The arrow's length, from the panel to its tip, and its width where it
    /// meets the panel.
    static let arrowLength: CGFloat = 13
    static let arrowWidth: CGFloat = 30
    /// The least space between the panel and the edges of the safe area.
    static let margin: CGFloat = 16

    /// Measured: the panel's fill and its actions' fill.
    static let lightFill = RGBA(red: 255, green: 255, blue: 255)
    static let darkFill = RGBA(red: 34, green: 34, blue: 35)
    static let lightButtonFill = RGBA(red: 237, green: 237, blue: 238)
    static let darkButtonFill = RGBA(red: 52, green: 52, blue: 55)
    /// The hairline around the panel and its arrow.
    static let lightEdge = RGBA(red: 0, green: 0, blue: 0, alpha: 40)
    static let darkEdge = RGBA(red: 255, green: 255, blue: 255, alpha: 64)
    static let edgeWidth: CGFloat = 0.5
    /// Assumed: the soft shadow around the panel.
    static let shadow = RGBA(red: 0, green: 0, blue: 0, alpha: 31)
    static let shadowBlur: Double = 40

    /// Registers the kinds of the dialog with the layout engine and the
    /// renderer.
    static func registerBehaviors() {
        NodeExtensions.registerOnce(kind: "ConfirmationDialog") {
            NodeBehavior(
                isPresentation: true,
                placePresentation: { engine, node, below in
                    engine.placeConfirmationDialog(node, over: below)
                }
            )
        }
        NodeExtensions.registerOnce(kind: "ConfirmationDialogPanel") {
            NodeBehavior(draw: { renderer, node, drawing, canvas in
                renderer.drawConfirmationDialogPanel(node, drawing: drawing, into: &canvas)
            })
        }
    }
}

extension LayoutEngine {
    /// Places a confirmation dialog's panel centered above the view it is
    /// attached to, with its arrow's tip on the view's top edge, or below the
    /// view when there is no room above it. The panel's `arrow` attribute
    /// records the tip as `x,y` and the side as `arrowEdge`.
    func placeConfirmationDialog(_ node: ViewNode, over below: [ViewNode]) -> ViewNode {
        typealias Metrics = ConfirmationDialogLayout
        var node = node
        let safeArea = device.safeArea
        node.frame = CGRect(origin: .zero, size: device.screenSize)
        guard var panel = node.children.first else { return node }
        let anchor =
            node.attributes["anchor"].flatMap { id in
                below.lazy.compactMap { $0.node(withID: NodeID(id))?.hitFrame }.first
            } ?? CGRect(x: safeArea.midX, y: safeArea.midY, width: 0, height: 0)

        // The panel is as wide as its widest line or action, up to the
        // width of the safe area.
        let maxWidth = safeArea.width - 2 * Metrics.margin
        let maxContent = maxWidth - 2 * Metrics.padding
        var widest: CGFloat = 0
        for child in panel.children {
            if child.kind == "Button" {
                let label = sizeThatFits(child, .unspecified, parentAxis: nil)
                widest = max(widest, label.width + 2 * Metrics.buttonPadding)
            } else {
                widest = max(widest, sizeThatFits(child, .unspecified, parentAxis: nil).width)
            }
        }
        let width = min(widest, maxContent) + 2 * Metrics.padding
        let contentWidth = width - 2 * Metrics.padding

        // The content's heights, top to bottom.
        var heights: [CGFloat] = []
        var spacings: [CGFloat] = []
        var previous: ViewNode?
        for child in panel.children {
            let isButton = child.kind == "Button"
            heights.append(
                isButton
                    ? Metrics.buttonHeight
                    : sizeThatFits(
                        child, ProposedSize(width: contentWidth, height: nil), parentAxis: nil
                    ).height)
            if let previous {
                spacings.append(
                    previous.kind == "Button"
                        ? Metrics.buttonSpacing
                        : isButton ? Metrics.textSpacing : Metrics.messageSpacing)
            } else {
                spacings.append(isButton ? Metrics.padding : Metrics.topPadding)
            }
            previous = child
        }
        let height =
            heights.reduce(0, +) + spacings.reduce(0, +) + Metrics.padding

        // Above the view when it fits, otherwise below.
        let fitsAbove =
            anchor.minY - Metrics.arrowLength - height >= safeArea.minY + Metrics.margin
        let tipY = fitsAbove ? anchor.minY : anchor.maxY
        let y = fitsAbove ? tipY - Metrics.arrowLength - height : tipY + Metrics.arrowLength
        var x = anchor.midX - width / 2
        x = min(max(x, safeArea.minX + Metrics.margin), safeArea.maxX - Metrics.margin - width)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let tipX = min(
            max(anchor.midX, frame.minX + Metrics.cornerRadius),
            frame.maxX - Metrics.cornerRadius)

        var top = frame.minY
        panel.children = panel.children.enumerated().map { index, child in
            top += spacings[index]
            let rect = CGRect(
                x: frame.minX + Metrics.padding, y: top, width: contentWidth,
                height: heights[index])
            top += heights[index]
            if child.kind == "Button" {
                return place(child, in: rect, parentAxis: nil)
            }
            let size = sizeThatFits(
                child, ProposedSize(width: contentWidth, height: nil), parentAxis: nil)
            return place(child, in: align(size, in: rect, .center), parentAxis: nil)
        }
        panel.frame = frame
        panel.attributes["arrow"] = "\(formatPoints(tipX)),\(formatPoints(tipY))"
        panel.attributes["arrowEdge"] = fitsAbove ? "bottom" : "top"
        node.children = [panel]
        return node
    }
}

// MARK: - Drawing

extension TreeRenderer {
    /// Draws a confirmation dialog's panel: its shadow, its bubble and arrow
    /// with a hairline edge, and a capsule behind each action.
    func drawConfirmationDialogPanel(
        _ node: ViewNode, drawing: NodeDrawing, into canvas: inout Canvas
    ) {
        typealias Metrics = ConfirmationDialogLayout
        let frame = drawing.frame
        let isDark = drawing.scheme == .dark
        func faded(_ color: RGBA) -> RGBA {
            var color = color
            color.alpha = UInt8((Double(color.alpha) * drawing.opacity).rounded())
            return color
        }
        let radius = min(Metrics.cornerRadius, min(frame.width, frame.height) / 2)
        canvas.drawShadow(
            of: frame, cornerRadius: radius, style: .continuous, color: faded(Metrics.shadow),
            blur: Metrics.shadowBlur)

        let tip = (node.attributes["arrow"] ?? "").split(separator: ",").compactMap {
            Double($0).map { CGFloat($0) }
        }
        let pointsDown = node.attributes["arrowEdge"] != "top"
        func arrow(outset: CGFloat) -> Path? {
            guard tip.count == 2 else { return nil }
            let half = Metrics.arrowWidth / 2 + outset
            let base = pointsDown ? frame.maxY - 1 : frame.minY + 1
            let direction: CGFloat = pointsDown ? 1 : -1
            let tipY = tip[1] + direction * outset
            // The tip is rounded.
            let shoulder: CGFloat = 3
            var path = Path()
            path.move(to: CGPoint(x: tip[0] - half, y: base))
            path.addLine(to: CGPoint(x: tip[0] - shoulder, y: tipY - direction * shoulder))
            path.addQuadCurve(
                to: CGPoint(x: tip[0] + shoulder, y: tipY - direction * shoulder),
                control: CGPoint(x: tip[0], y: tipY))
            path.addLine(to: CGPoint(x: tip[0] + half, y: base))
            path.closeSubpath()
            return path
        }

        // The edge is the bubble and arrow, a hairline larger, under them.
        let edge = faded(isDark ? Metrics.darkEdge : Metrics.lightEdge)
        let width = Metrics.edgeWidth
        canvas.fill(
            frame.insetBy(dx: -width, dy: -width), cornerRadius: radius + width,
            style: .continuous, color: edge)
        if let outline = arrow(outset: width) { canvas.fill(outline, color: edge) }
        let fill = faded(isDark ? Metrics.darkFill : Metrics.lightFill)
        canvas.fill(frame, cornerRadius: radius, style: .continuous, color: fill)
        if let shape = arrow(outset: 0) { canvas.fill(shape, color: fill) }

        let buttonFill = faded(isDark ? Metrics.darkButtonFill : Metrics.lightButtonFill)
        for button in node.children where button.kind == "Button" {
            guard let cell = button.frame else { continue }
            var color = buttonFill
            if button.id == pressedNodeID {
                color = faded(isDark ? Metrics.darkEdge : Metrics.lightEdge)
                canvas.fill(cell, cornerRadius: cell.height / 2, color: buttonFill)
            }
            canvas.fill(cell, cornerRadius: cell.height / 2, color: color)
        }
    }
}
