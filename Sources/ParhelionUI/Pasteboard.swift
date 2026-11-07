import Foundation

/// A type that can go on the pasteboard, standing in for CoreTransferable's
/// `Transferable`, which Linux does not have.
public protocol Transferable {}

extension String: Transferable {}
extension URL: Transferable {}
extension Data: Transferable {}

/// A compile-only stub: a button that pastes nothing. Issue #65 pastes.
public struct PasteButton: View {
    public init<T: Transferable>(
        payloadType: T.Type, onPaste: @escaping @MainActor ([T]) -> Void
    ) {}

    public var body: some View {
        Button("Paste") {}
    }
}
