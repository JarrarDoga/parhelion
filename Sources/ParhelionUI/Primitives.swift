#if canImport(Foundation)
import Foundation
#endif

/// A view that displays one or more lines of read-only text.
public struct Text: View, Equatable, Sendable {
    public typealias Body = Never

    let content: String

    public init(_ content: some StringProtocol) {
        self.content = String(content)
    }

    public init(verbatim content: String) {
        self.content = content
    }

    public var body: Never {
        fatalError("Text is a primitive view and has no body.")
    }
}

extension Text: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        [ViewNode(id: path.appending("Text").id, kind: "Text", attributes: ["text": content])]
    }
}

/// A view that displays an image.
public struct Image: View, Equatable, Sendable {
    public typealias Body = Never

    /// The relative size of a symbol image.
    public enum Scale: String, Sendable {
        case small, medium, large
    }

    enum Source: Equatable, Sendable {
        case named(String)
        case systemName(String)
    }

    let source: Source

    public init(_ name: String) {
        source = .named(name)
    }

    public init(systemName: String) {
        source = .systemName(systemName)
    }

    public var body: Never {
        fatalError("Image is a primitive view and has no body.")
    }
}

extension Image: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let attributes: [String: String] =
            switch source {
            case .named(let name): ["name": name]
            case .systemName(let name): ["systemName": name]
            }
        return [ViewNode(id: path.appending("Image").id, kind: "Image", attributes: attributes)]
    }
}

/// A control that performs an action when tapped.
public struct Button<Label: View>: View {
    public typealias Body = Never

    let label: Label
    let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: Never {
        fatalError("Button is a primitive view and has no body.")
    }
}

extension Button where Label == Text {
    public init(_ title: some StringProtocol, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }
}

extension Button: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("Button")
        evaluator.registerAction(action, for: ownPath.id)
        return [
            ViewNode(
                id: ownPath.id,
                kind: "Button",
                children: evaluator.evaluate(label, at: ownPath)
            )
        ]
    }
}

/// A flexible space that expands along the major axis of its stack.
public struct Spacer: View, Sendable {
    public typealias Body = Never

    let minLength: CGFloat?

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer is a primitive view and has no body.")
    }
}

extension Spacer: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        var attributes: [String: String] = [:]
        if let minLength { attributes["minLength"] = formatLength(minLength) }
        return [ViewNode(id: path.appending("Spacer").id, kind: "Spacer", attributes: attributes)]
    }
}

func formatLength(_ value: CGFloat) -> String {
    value.rounded() == value ? String(Int(value)) : String(Double(value))
}
