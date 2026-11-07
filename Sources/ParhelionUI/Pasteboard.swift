import Foundation

/// A type that can go on the pasteboard, standing in for CoreTransferable's
/// `Transferable`, which Linux does not have.
public protocol Transferable {}

extension String: Transferable {}
extension URL: Transferable {}
extension Data: Transferable {}

/// A button that pastes what is on the pasteboard, mirroring SwiftUI's
/// `PasteButton`.
///
/// The pasteboard holds text: what the focused ``TextField`` copied, what a
/// window host read from the system clipboard, or what a test or an agent
/// set (`ViewHost.pasteboardText`, or the `set_clipboard` tool). A button for
/// `String` pastes the text; for `URL`, the text if it is a URL with a
/// scheme; for `Data`, the text's UTF-8 bytes. It is disabled while the
/// pasteboard has nothing of its type, as SwiftUI's is.
///
/// Assumed: iOS draws the button itself, a tinted capsule labeled "Paste"
/// with a clipboard symbol; this draws a prominent button with the same
/// label. SwiftUI's `init(supportedContentTypes:payloadAction:)` needs
/// `UTType` and `NSItemProvider`, which Linux does not have.
public struct PasteButton: View {
    public typealias Body = Never

    /// The action that pastes the text, or `nil` if the text has nothing of
    /// this button's type.
    let payload: @MainActor (String) -> (@MainActor () -> Void)?

    public init<T: Transferable>(
        payloadType: T.Type, onPaste: @escaping @MainActor ([T]) -> Void
    ) {
        payload = { text in
            guard let items = Self.items(of: T.self, in: text) else { return nil }
            return { onPaste(items) }
        }
    }

    public var body: Never {
        fatalError("PasteButton is a primitive view and has no body.")
    }

    private static func items<T>(of type: T.Type, in text: String) -> [T]? {
        guard !text.isEmpty else { return nil }
        if let strings = [text] as? [T] { return strings }
        if let data = [Data(text.utf8)] as? [T] { return data }
        if let url = URL(string: text), url.scheme != nil, let urls = [url] as? [T] {
            return urls
        }
        return nil
    }
}

extension PasteButton: PrimitiveView {
    func makeNodes(in evaluator: Evaluator, at path: ViewPath) -> [ViewNode] {
        let ownPath = path.appending("PasteButton")
        let action = evaluator.host.pasteboardText.flatMap(payload)
        let button = Button(action: action ?? {}) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        let children = evaluator.withEnvironment({
            if case .builtIn(.automatic) = $0.buttonStyle {
                $0.buttonStyle = .builtIn(.borderedProminent)
            }
            if action == nil { $0.isEnabled = false }
        }) {
            evaluator.evaluate(button, at: ownPath)
        }
        return [ViewNode(id: ownPath.id, kind: "PasteButton", children: children)]
    }
}
