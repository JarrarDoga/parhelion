#if canImport(Foundation)
import Foundation
#endif

/// When a tab bar shrinks, mirroring SwiftUI's `TabBarMinimizeBehavior`.
///
/// Assumed: on iPhone, `.automatic` is `.never`, as in iOS 26.
public struct TabBarMinimizeBehavior: Hashable, Sendable {
    let name: String

    public static let automatic = TabBarMinimizeBehavior(name: "automatic")
    public static let onScrollDown = TabBarMinimizeBehavior(name: "onScrollDown")
    public static let onScrollUp = TabBarMinimizeBehavior(name: "onScrollUp")
    public static let never = TabBarMinimizeBehavior(name: "never")

    /// Whether scrolling can minimize the bar.
    var minimizesOnScroll: Bool { self == .onScrollDown || self == .onScrollUp }
}

struct TabBarMinimizeBehaviorKey: EnvironmentKey {
    static var defaultValue: TabBarMinimizeBehavior { .automatic }
}

extension EnvironmentValues {
    var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        get { self[TabBarMinimizeBehaviorKey.self] }
        set { self[TabBarMinimizeBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets when the enclosing tab view's bar shrinks to a small capsule:
    /// when the content scrolls down, or up, or never. The bar returns when
    /// the content scrolls the other way, or when a tap lands on the small
    /// capsule. A tab view minimizes only for content that is one scroll
    /// view, possibly inside a navigation stack.
    public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View {
        environment(\.tabBarMinimizeBehavior, behavior)
    }
}

// MARK: - Layout defaults

extension LayoutDefaults {
    /// The height of the minimized tab bar. Assumed: 48 points.
    static let tabBarMinimizedHeight: CGFloat = 48

    /// The width of the minimized tab bar, which shows only the selected
    /// tab's symbol. Assumed: 64 points.
    static let tabBarMinimizedWidth: CGFloat = 64

    /// How far the content must move between two layouts to count as a
    /// scroll in a direction. Assumed: half a point.
    static let tabBarMinimizeThreshold: CGFloat = 0.5

    /// The animation of the bar and the accessory minimizing and returning.
    /// Assumed: 0.35 seconds, ease in and out.
    static let tabBarMinimizeAnimation = Animation.easeInOut(duration: 0.35)
}

// MARK: - State

/// Which tab bars are minimized, and where their content was scrolled to
/// when that was last decided. The host owns it with the scroll offsets.
struct TabBarScrollState {
    var minimized: Set<NodeID> = []
    /// The scroll view whose offset is tracked, and its offset, by tab view.
    var tracked: [NodeID: (scrollView: NodeID, offset: CGFloat)] = [:]
    /// Set when a tab bar minimized or returned, so that the host evaluates
    /// the tree again with the new placement and animates the change.
    var changed = false
    /// The tab views whose bar changed since the last layout. The bar's new
    /// height changes the content's bottom inset, and so can clamp its
    /// offset; the next layout takes that offset without reading it as a
    /// scroll.
    var settling: Set<NodeID> = []

    mutating func set(_ id: NodeID, minimized isMinimized: Bool) {
        guard minimized.contains(id) != isMinimized else { return }
        if isMinimized { minimized.insert(id) } else { minimized.remove(id) }
        changed = true
        settling.insert(id)
    }
}

extension Evaluator {
    /// Whether a tab view's bar is minimized now.
    func isTabBarMinimized(_ id: NodeID) -> Bool {
        environment.tabBarMinimizeBehavior.minimizesOnScroll
            && host.scrolling.tabBars.minimized.contains(id)
    }

    /// Brings a minimized tab bar back, as a tap on it does.
    @MainActor
    static func expandTabBar(_ id: NodeID, in host: ViewHost) {
        guard host.scrolling.tabBars.minimized.contains(id) else { return }
        withAnimation(LayoutDefaults.tabBarMinimizeAnimation) {
            host.scrolling.tabBars.set(id, minimized: false)
            host.scrolling.tabBars.changed = false
            host.setNeedsUpdate()
        }
    }
}

// MARK: - Layout

extension LayoutEngine {
    /// Decides, from how far each tab view's content scrolled since the last
    /// layout, whether its bar is minimized. A change sets
    /// `scrolling.tabBars.changed`, and the host lays out again.
    func updateTabBarMinimization(in root: ViewNode) {
        for tabView in root.allNodes where tabView.kind == "TabView" {
            let id = tabView.id
            guard let name = tabView.attributes["tabBarMinimizeBehavior"] else {
                scrolling.tabBars.tracked[id] = nil
                scrolling.tabBars.set(id, minimized: false)
                continue
            }
            guard let scrollView = TreeRenderer.scrollView(under: tabView),
                let offset = scrolling.metrics[scrollView.id]?.offset.y
            else {
                scrolling.tabBars.tracked[id] = nil
                scrolling.tabBars.set(id, minimized: false)
                continue
            }
            let previous = scrolling.tabBars.tracked[id]
            scrolling.tabBars.tracked[id] = (scrollView.id, offset)
            if scrolling.tabBars.settling.remove(id) != nil,
                previous?.scrollView == scrollView.id
            {
                continue
            }
            // Another screen starts with the bar open.
            guard let previous, previous.scrollView == scrollView.id else {
                scrolling.tabBars.set(id, minimized: false)
                continue
            }
            let threshold = LayoutDefaults.tabBarMinimizeThreshold
            let movedDown = offset - previous.offset > threshold
            let movedUp = previous.offset - offset > threshold
            let (minimizing, restoring) =
                name == TabBarMinimizeBehavior.onScrollDown.name
                ? (movedDown, movedUp || offset <= threshold)
                : (movedUp, movedDown)
            if restoring {
                scrolling.tabBars.set(id, minimized: false)
            } else if minimizing {
                scrolling.tabBars.set(id, minimized: true)
            }
        }
    }
}
