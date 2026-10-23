#if canImport(Foundation)
import Foundation
#endif

/// A sheet, full-screen cover, or alert that a view asked to present.
///
/// Views register presentations while they are evaluated. The host then
/// evaluates each presentation's content and adds it to the root of the tree,
/// above the app's content, in the order the views asked. The last one is in
/// front and is the only one that receives input.
struct Presentation {
    let id: NodeID
    /// Sets the presenting binding back, which removes the presentation.
    let dismiss: @MainActor () -> Void
    /// Runs after the presentation is dismissed, by any means.
    let onDismiss: (() -> Void)?
    /// Evaluates the presentation's content into its node.
    let makeNode: @MainActor (Evaluator) -> ViewNode
}

extension ViewNode {
    /// Whether this node is a sheet, a full-screen cover, an alert, or a
    /// picker's menu at the root of the tree.
    var isPresentation: Bool {
        kind == "Sheet" || kind == "FullScreenCover" || kind == "Alert" || kind == "Menu"
    }
}

// MARK: - Sheets

/// A height a sheet can rest at, mirroring SwiftUI's `PresentationDetent`.
///
/// Parhelion shows a sheet at the smallest of its detents.
public struct PresentationDetent: Hashable, Sendable {
    let name: String

    /// A sheet that covers about half of the screen.
    public static let medium = PresentationDetent(name: "medium")
    /// A sheet that covers the screen below the status bar.
    public static let large = PresentationDetent(name: "large")

    /// A sheet that covers a fraction of the screen's height.
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent {
        PresentationDetent(name: "fraction:\(formatPoints(fraction))")
    }

    /// A sheet with a fixed height in points.
    public static func height(_ height: CGFloat) -> PresentationDetent {
        PresentationDetent(name: "height:\(formatPoints(height))")
    }
}

extension View {
    /// Presents a sheet while `isPresented` is `true`.
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PresentingView(
            content: self,
            kind: "Sheet",
            identity: isPresented.wrappedValue ? "sheet" : nil,
            dismiss: { isPresented.wrappedValue = false },
            onDismiss: onDismiss,
            presented: content
        )
    }

    /// Presents a sheet for an item while the item is not `nil`. A different
    /// item presents a new sheet, with new state.
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let current = item.wrappedValue
        return PresentingView(
            content: self,
            kind: "Sheet",
            identity: current.map { "sheet[\($0.id)]" },
            dismiss: { item.wrappedValue = nil },
            onDismiss: onDismiss,
            presented: { current.map(content) }
        )
    }

    /// Presents a view that covers the whole screen while `isPresented` is
    /// `true`.
    public func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PresentingView(
            content: self,
            kind: "FullScreenCover",
            identity: isPresented.wrappedValue ? "fullScreenCover" : nil,
            dismiss: { isPresented.wrappedValue = false },
            onDismiss: onDismiss,
            presented: content
        )
    }

    /// Presents a view that covers the whole screen for an item while the
    /// item is not `nil`.
    public func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let current = item.wrappedValue
        return PresentingView(
            content: self,
            kind: "FullScreenCover",
            identity: current.map { "fullScreenCover[\($0.id)]" },
            dismiss: { item.wrappedValue = nil },
            onDismiss: onDismiss,
            presented: { current.map(content) }
        )
    }

    /// Sets the heights a sheet can rest at. Parhelion shows the sheet at the
    /// smallest one.
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        PresentationOptionView(content: self, option: .detents(detents))
    }

    /// Sets whether a sheet shows a grabber at its top. With `.automatic`,
    /// it shows one when it has more than one detent.
    public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        PresentationOptionView(content: self, option: .dragIndicator(visibility))
    }
}

/// Whether a part of the interface is shown, mirroring SwiftUI's
/// `Visibility`.
public enum Visibility: String, CaseIterable, Hashable, Sendable {
    /// Shown or hidden as the system chooses.
    case automatic
    /// Shown.
    case visible
    /// Hidden.
    case hidden
}

struct IsInSheetKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the view is in a sheet, whose navigation bar leaves room
    /// above its buttons.
    var isInSheet: Bool {
        get { self[IsInSheetKey.self] }
        set { self[IsInSheetKey.self] = newValue }
    }
}

/// A view that presents a sheet or a full-screen cover.
struct PresentingView<Content: View, Presented: View>: View {
    typealias Body = Never

    let content: Content
    let kind: String
    /// The presentation's path component, or `nil` when nothing is
    /// presented.
    let identity: String?
    let dismiss: @MainActor () -> Void
    let onDismiss: (() -> Void)?
    let presented: () -> Presented?

    var body: Never {
        fatalError("PresentingView is a primitive view and has no body.")
    }
}

extension PresentingView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard let identity, let view = presented() else { return nodes }
        let ownPath = path.appending(identity)
        let kind = kind
        var environment = evaluator.environment.presenting(dismiss: dismiss)
        environment.isInSheet = kind == "Sheet"
        evaluator.registerPresentation(
            Presentation(id: ownPath.id, dismiss: dismiss, onDismiss: onDismiss) { evaluator in
                evaluator.presentationDetents = []
                evaluator.presentationDragIndicator = .automatic
                let children = evaluator.withEnvironment({ $0 = environment }) {
                    evaluator.evaluate(view, at: ownPath)
                }
                var attributes: [String: String] = [:]
                if !evaluator.presentationDetents.isEmpty {
                    attributes["detents"] = evaluator.presentationDetents.map(\.name).sorted()
                        .joined(separator: ",")
                }
                if evaluator.presentationDragIndicator != .automatic {
                    attributes["dragIndicator"] = evaluator.presentationDragIndicator.rawValue
                }
                return ViewNode(
                    id: ownPath.id, kind: kind, attributes: attributes, children: children)
            }
        )
        return nodes
    }
}

/// A view that sets the detents or the grabber of the sheet it is in.
struct PresentationOptionView<Content: View>: View {
    typealias Body = Never

    enum Option {
        case detents(Set<PresentationDetent>)
        case dragIndicator(Visibility)
    }

    let content: Content
    let option: Option

    var body: Never {
        fatalError("PresentationOptionView is a primitive view and has no body.")
    }
}

extension PresentationOptionView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        switch option {
        case .detents(let detents):
            evaluator.presentationDetents.formUnion(detents)
        case .dragIndicator(let visibility):
            evaluator.presentationDragIndicator = visibility
        }
        return evaluator.evaluate(content, at: path)
    }
}

// MARK: - Alerts

extension View {
    /// Presents an alert with a title and actions while `isPresented` is
    /// `true`. Every action dismisses the alert after it runs. Without
    /// actions, the alert has an OK button.
    public func alert<Actions: View>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        AlertView(
            content: self, title: String(title), isPresented: isPresented,
            actions: isPresented.wrappedValue ? actions() : nil, message: EmptyView?.none)
    }

    /// Presents an alert with a title, a message, and actions while
    /// `isPresented` is `true`.
    public func alert<Actions: View, Message: View>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> some View {
        let shown = isPresented.wrappedValue
        return AlertView(
            content: self, title: String(title), isPresented: isPresented,
            actions: shown ? actions() : nil, message: shown ? message() : nil)
    }

    /// Presents an alert about some data while `isPresented` is `true` and
    /// the data is not `nil`.
    public func alert<Actions: View, T>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> Actions
    ) -> some View {
        let data = isPresented.wrappedValue ? data : nil
        return AlertView(
            content: self, title: String(title), isPresented: isPresented,
            actions: data.map(actions), message: EmptyView?.none)
    }

    /// Presents an alert with a message about some data while `isPresented`
    /// is `true` and the data is not `nil`.
    public func alert<Actions: View, Message: View, T>(
        _ title: some StringProtocol,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> Actions,
        @ViewBuilder message: (T) -> Message
    ) -> some View {
        let data = isPresented.wrappedValue ? data : nil
        return AlertView(
            content: self, title: String(title), isPresented: isPresented,
            actions: data.map(actions), message: data.map(message))
    }
}

/// A view that presents an alert. `actions` is `nil` while the alert is not
/// presented.
struct AlertView<Content: View, Actions: View, Message: View>: View {
    typealias Body = Never

    let content: Content
    let title: String
    let isPresented: Binding<Bool>
    let actions: Actions?
    let message: Message?

    var body: Never {
        fatalError("AlertView is a primitive view and has no body.")
    }
}

extension AlertView: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let nodes = evaluator.evaluate(content, at: path)
        guard let actions else { return nodes }
        let ownPath = path.appending("alert")
        let isPresented = isPresented
        let dismiss: @MainActor () -> Void = { isPresented.wrappedValue = false }
        var environment = evaluator.environment.presenting(dismiss: dismiss)
        // An alert draws its buttons as capsules, whatever style is set
        // around it.
        environment.buttonContext = .alert
        environment.buttonStyle = .builtIn(.automatic)
        environment.isInSheet = false
        let title = title
        let message = message
        evaluator.registerPresentation(
            Presentation(id: ownPath.id, dismiss: dismiss, onDismiss: nil) { evaluator in
                evaluator.withEnvironment({ $0 = environment }) {
                    var buttons: [ViewNode] = []
                    var fields: [ViewNode] = []
                    for node in evaluator.evaluate(actions, at: ownPath.appending("actions")) {
                        if node.kind == "Button" {
                            evaluator.appendToAction(for: node.id, dismiss)
                            buttons.append(node)
                        } else {
                            fields.append(node)
                        }
                    }
                    if buttons.isEmpty {
                        let okPath = ownPath.appending("ok")
                        evaluator.registerAction(dismiss, for: okPath.id)
                        buttons.append(
                            ViewNode(
                                id: okPath.id, kind: "Button",
                                children: [
                                    ViewNode(
                                        id: okPath.appending("Text").id, kind: "Text",
                                        attributes: ["text": "OK"])
                                ]))
                    }
                    // The cancel button goes first in a row of two, and last
                    // in a column.
                    if let cancel = buttons.firstIndex(where: { $0.attributes["role"] == "cancel" })
                    {
                        let button = buttons.remove(at: cancel)
                        if buttons.count == 1 {
                            buttons.insert(button, at: 0)
                        } else {
                            buttons.append(button)
                        }
                    }
                    // Assumed: the title is semibold 17 points, which is
                    // `headline`, in the iOS 27 UI Kit.
                    let titleNode = ViewNode(
                        id: ownPath.appending("title").id, kind: "Text",
                        attributes: ["text": title, "font": Font.headline.resolved().attribute])
                    let messageNodes =
                        message.map { evaluator.evaluate($0, at: ownPath.appending("message")) }
                        ?? []
                    return ViewNode(
                        id: ownPath.id, kind: "Alert",
                        children: [titleNode] + messageNodes + fields + buttons)
                }
            }
        )
        return nodes
    }
}

// MARK: - Button roles

/// The purpose of a button, mirroring SwiftUI's `ButtonRole`.
///
/// A destructive button's label is red. In an alert, a cancel button goes
/// first in a row of two buttons and last in a column.
public struct ButtonRole: Equatable, Sendable {
    let name: String

    /// A button that deletes data or does something that cannot be undone.
    public static let destructive = ButtonRole(name: "destructive")
    /// A button that cancels the current operation.
    public static let cancel = ButtonRole(name: "cancel")
}
