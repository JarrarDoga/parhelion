import Foundation

extension View {
    /// A compile-only stub: the view is not rotated. Issue #61 rotates it.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        self
    }

    /// A compile-only stub: the view is not blurred. Issue #61 blurs it.
    public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        self
    }

    /// A compile-only stub: the view is not masked. Issue #61 masks it.
    public func mask<Mask: View>(
        alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self
    }
}
