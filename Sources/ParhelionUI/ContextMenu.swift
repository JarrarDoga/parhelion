#if canImport(Foundation)
import Foundation
#endif

extension View {
    /// Adds a menu that a long press on this view opens, mirroring SwiftUI's
    /// `contextMenu(menuItems:)`.
    ///
    /// The long press lifts the view to 1.03 times its size and blurs the
    /// screen behind it; the menu sits below it, or above when there is no
    /// room. Drive it with ``ViewHost/longPress(at:duration:)``, or hold the
    /// pointer for half a second with ``ViewHost/pointerDown(at:)`` and
    /// ``ViewHost/advanceTime(by:)``; a long press does not also tap the
    /// view. Parhelion
    /// shows the lifted view as a copy, so state in the view starts afresh.
    public func contextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        ContextMenuView(content: self, items: menuItems(), preview: nil)
    }

    /// Adds a menu that a long press opens, with a view of its own in place
    /// of the lifted view, mirroring SwiftUI's `contextMenu(menuItems:preview:)`.
    public func contextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        ContextMenuView(content: self, items: menuItems(), preview: AnyView(preview()))
    }
}

/// A view with a context menu. Its nodes are its content's, with a long press
/// handler on each.
struct ContextMenuView<Content: View, MenuItems: View>: View {
    typealias Body = Never

    let content: Content
    let items: MenuItems
    /// The view shown lifted, or `nil` for a copy of the content.
    let preview: AnyView?

    var body: Never {
        fatalError("ContextMenuView is a primitive view and has no body.")
    }
}

/// Whether a context menu is open, and the node it lifted. Kept in host
/// storage under the view; it is not `Codable`, so hot reload does not open
/// a menu again.
struct ContextMenuState {
    var anchor: NodeID?
}

extension ContextMenuView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("ContextMenu")
        let nodes = evaluator.evaluate(content, at: path)
        let box = evaluator.controlBox(ownPath.id, "contextMenu", initialValue: ContextMenuState())
        let close: @MainActor () -> Void = {
            box.value.anchor = nil
            box.host?.setNeedsUpdate()
        }
        if evaluator.environment.isEnabled {
            for node in nodes {
                let id = node.id
                let open: @MainActor () -> Void = {
                    box.value.anchor = id
                    box.host?.setNeedsUpdate()
                }
                // `ViewHost.longPress(at:duration:)` calls the handler; a
                // pointer held in the window goes through the gesture.
                evaluator.registerInputHandlers(
                    NodeInputHandlers(longPress: { _, _ in open() }), for: id)
                evaluator.registerLongPress(for: id, perform: open)
            }
        }
        guard let anchor = box.value.anchor, nodes.contains(where: { $0.id == anchor }) else {
            return nodes
        }

        let presentationID = ownPath.appending("presentation").id
        let environment = evaluator.environment
        let lifted: AnyView = preview ?? AnyView(content)
        let isCustomPreview = preview != nil
        let background = environment.isInList ? "groupedRowBackground" : "background"
        MenuLayout.registerBehaviors()
        let previewPath = ViewPath().appending("ContextMenuPreview[\(presentationID.rawValue)]")
        let menuItems = AnyView(items)
        evaluator.registerPresentation(
            Presentation(id: presentationID, dismiss: close, onDismiss: nil) { evaluator in
                // A tap outside the lifted view and the menu closes it.
                evaluator.registerAction(close, for: presentationID)
                let liftedNodes = evaluator.withEnvironment({
                    $0 = environment
                    $0.isInList = false
                    $0 = evaluator.startingPresentation(in: $0)
                }) {
                    evaluator.evaluate(lifted, at: previewPath)
                }
                var preview = ViewNode(
                    id: presentationID.appending("preview"), kind: "ContextMenuPreview",
                    attributes: [
                        "custom": isCustomPreview ? "true" : "false", "background": background,
                    ],
                    children: liftedNodes)
                preview.modifiers = [
                    .shadow(color: "black@0.25", radius: 12, x: 0, y: 6),
                    .scaleEffect(
                        x: MenuLayout.liftScale, y: MenuLayout.liftScale,
                        anchor: .init(x: 0.5, y: 0.5)),
                ]
                let panel = MenuPresenter.panel(
                    id: presentationID.appending("panel"), items: menuItems,
                    environment: environment, close: close, in: evaluator,
                    at: ViewPath().appending("MenuPanel[\(presentationID.rawValue)]"))
                return ViewNode(
                    id: presentationID, kind: "ContextMenu",
                    attributes: ["anchor": anchor.rawValue, "label": "Dismiss Menu"],
                    children: [preview, panel])
            })
        return nodes
    }
}
