/// Where a search field goes, mirroring SwiftUI's `SearchFieldPlacement`.
public struct SearchFieldPlacement: Hashable, Sendable {
    /// How the field shows in the navigation bar.
    public struct NavigationBarDrawerDisplayMode: Hashable, Sendable {
        let name: String

        public static let automatic = NavigationBarDrawerDisplayMode(name: "automatic")
        public static let always = NavigationBarDrawerDisplayMode(name: "always")
    }

    let name: String

    public static let automatic = SearchFieldPlacement(name: "automatic")
    public static let toolbar = SearchFieldPlacement(name: "toolbar")
    public static let toolbarPrincipal = SearchFieldPlacement(name: "toolbarPrincipal")
    public static let sidebar = SearchFieldPlacement(name: "sidebar")
    public static let navigationBarDrawer = SearchFieldPlacement(name: "navigationBarDrawer")

    public static func navigationBarDrawer(
        displayMode: NavigationBarDrawerDisplayMode
    ) -> SearchFieldPlacement {
        SearchFieldPlacement(name: "navigationBarDrawer.\(displayMode.name)")
    }
}

struct IsSearchingKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// Whether the user is searching. Always `false` until issue #59.
    public var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }
}

extension View {
    /// A compile-only stub that draws no search field. Issue #59 draws it.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        self
    }

    /// A compile-only stub that draws no search field. Issue #59 draws it.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        self
    }
}
