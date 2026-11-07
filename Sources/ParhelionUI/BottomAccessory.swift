import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// Where a tab view's bottom accessory is, mirroring SwiftUI's
/// `TabViewBottomAccessoryPlacement`.
public enum TabViewBottomAccessoryPlacement: Equatable, Sendable {
    /// Above the tab bar, across its width.
    case expanded
    /// Next to the minimized tab bar.
    case inline
}

struct TabViewBottomAccessoryPlacementKey: EnvironmentKey {
    static var defaultValue: TabViewBottomAccessoryPlacement? { nil }
}

struct TabViewBottomAccessoryContentKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

extension EnvironmentValues {
    /// Where the bottom accessory is. `nil` outside one.
    public var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement? {
        get { self[TabViewBottomAccessoryPlacementKey.self] }
        set { self[TabViewBottomAccessoryPlacementKey.self] = newValue }
    }

    /// The accessory that the enclosing tab view shows, if any.
    var bottomAccessoryContent: AnyView? {
        get { self[TabViewBottomAccessoryContentKey.self] }
        set { self[TabViewBottomAccessoryContentKey.self] = newValue }
    }
}

extension View {
    /// Shows `content` in a glass capsule above the tab bar of the enclosing
    /// tab view. While the tab bar is minimized, the accessory sits next to
    /// it, and ``EnvironmentValues/tabViewBottomAccessoryPlacement`` is
    /// ``TabViewBottomAccessoryPlacement/inline``.
    public func tabViewBottomAccessory<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        environment(\.bottomAccessoryContent, AnyView(content()))
    }

    /// Shows `content` in a glass capsule above the tab bar of the enclosing
    /// tab view when `isEnabled` is `true`.
    public func tabViewBottomAccessory<Content: View>(
        isEnabled: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        environment(\.bottomAccessoryContent, isEnabled ? AnyView(content()) : nil)
    }
}

// MARK: - Layout defaults

extension LayoutDefaults {
    /// The height of the bottom accessory's capsule. Assumed: 48 points,
    /// the height of the minimized tab bar it lines up with.
    static let bottomAccessoryHeight: CGFloat = 48

    /// The space between the bottom accessory and the tab bar above which it
    /// sits, or beside which it sits when the bar is minimized. Assumed:
    /// 8 points, the tab bar's own spacing to its search circle.
    static let bottomAccessorySpacing: CGFloat = 8

    /// The space between the accessory's capsule and its content. Assumed:
    /// 16 points.
    static let bottomAccessoryPadding: CGFloat = 16
}

// MARK: - Evaluation

extension Evaluator {
    /// The node of the tab view's bottom accessory, or none. The accessory is
    /// evaluated with the placement it has now, so a view that reads the
    /// placement from the environment changes with the tab bar.
    func bottomAccessoryNodes(at path: ViewPath, minimized: Bool) -> [ViewNode] {
        guard let accessory = environment.bottomAccessoryContent else { return [] }
        NodeExtensions.registerOnce(kind: "TabViewBottomAccessory") { .bottomAccessory }
        let ownPath = path.appending("TabViewBottomAccessory")
        let content = withEnvironment({
            $0.tabViewBottomAccessoryPlacement = minimized ? .inline : .expanded
            $0.bottomAccessoryContent = nil
        }) {
            evaluate(accessory, at: ownPath)
        }
        return [
            ViewNode(
                id: ownPath.id, kind: "TabViewBottomAccessory",
                attributes: ["placement": minimized ? "inline" : "expanded"], children: content)
        ]
    }
}

extension NodeBehavior {
    /// The accessory is a glass capsule. The tab view places it and its
    /// content.
    fileprivate static let bottomAccessory = NodeBehavior(
        draw: { _, node, drawing, canvas in
            let frame = drawing.frame
            canvas.drawGlass(
                frame, cornerRadius: frame.height / 2, material: drawing.palette.smallGlass,
                opacity: drawing.opacity)
        })
}

// MARK: - Layout

extension LayoutEngine {
    /// Places the accessory in its capsule, with its content centered in the
    /// capsule less its padding.
    func placeBottomAccessory(_ accessory: ViewNode, in rect: CGRect) -> ViewNode {
        var accessory = accessory
        accessory.frame = rect
        let padding = LayoutDefaults.bottomAccessoryPadding
        let inner = CGRect(
            x: rect.minX + padding, y: rect.minY, width: max(rect.width - 2 * padding, 0),
            height: rect.height)
        accessory.children = placeCentered(accessory.children, id: accessory.id, in: inner)
        return accessory
    }
}
