import Foundation
import Testing

@testable import ParhelionUI

/// The README's images of the dark appearance and of large Dynamic Type
/// sizes, drawn from the Tasks, Tabs, and Settings examples' screens.
@MainActor
enum AppearanceGallery {
    enum Screen: String, CaseIterable {
        case tasksListDark = "tasks-list-dark"
        case tasksAlertDark = "tasks-alert-dark"
        case tasksSheetDark = "tasks-sheet-dark"
        case tabsPlacesDark = "tabs-places-dark"
        /// The Settings example with its Appearance picker set to Dark,
        /// which prefers the dark color scheme on a light device.
        case settingsDark = "settings-dark"
        /// The Settings example's open Appearance menu in dark.
        case settingsMenuDark = "settings-menu-dark"
        case tasksListAccessibility = "tasks-list-accessibility2"
        case settingsLargeText = "settings-xxxlarge"
    }

    static func host(showing screen: Screen) throws -> ViewHost {
        switch screen {
        case .tasksListDark: return try dark(TasksScreens.host(showing: .list))
        case .tasksAlertDark: return try dark(TasksScreens.host(showing: .alert))
        case .tasksSheetDark: return try dark(TasksScreens.host(showing: .sheet))
        case .tabsPlacesDark: return try dark(TabsScreens.host(showing: .places))
        case .settingsDark, .settingsMenuDark:
            let host = try SettingsScreens.host(showing: .top)
            try host.tapButton(labeled: "Automatic")
            host.advanceTime(by: 2)
            try host.tapButton(labeled: "Dark")
            host.advanceTime(by: 2)
            if screen == .settingsMenuDark {
                try host.tapButton(labeled: "Dark")
                host.advanceTime(by: 2)
            }
            return host
        case .tasksListAccessibility:
            let host = try TasksScreens.host(showing: .list)
            host.dynamicTypeSize = .accessibility2
            return host
        case .settingsLargeText:
            let host = try SettingsScreens.host(showing: .top)
            host.dynamicTypeSize = .xxxLarge
            return host
        }
    }

    private static func dark(_ host: ViewHost) -> ViewHost {
        host.colorScheme = .dark
        return host
    }

    /// A screen as the README shows it: at 2× with the status bar and the
    /// home indicator, as `--png` draws.
    static func readmeImage(_ screen: Screen) throws -> Data {
        try host(showing: screen).render(scale: 2, chrome: .systemBars).pngData()
    }

    static func readmeImageURL(_ screen: Screen, in directory: URL? = nil) -> URL {
        (directory ?? TasksScreens.repository.appendingPathComponent("docs/images"))
            .appendingPathComponent("\(screen.rawValue).png")
    }
}

@MainActor
@Suite("Appearance gallery")
struct AppearanceGalleryTests {
    /// Rendering is deterministic, so the README's images must match a fresh
    /// render. After an intended rendering change, regenerate them with
    /// `PARHELION_README_IMAGES=docs/images swift test --filter writeAppearanceReadmeImages`.
    @Test(
        "The README's dark and Dynamic Type images match a fresh render",
        arguments: AppearanceGallery.Screen.allCases)
    func readmeImages(_ screen: AppearanceGallery.Screen) throws {
        let committed = try Data(contentsOf: AppearanceGallery.readmeImageURL(screen))
        #expect(try AppearanceGallery.readmeImage(screen) == committed)
    }

    @Test(
        "Write the README's dark and Dynamic Type images",
        .enabled(if: ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] != nil)
    )
    func writeAppearanceReadmeImages() throws {
        let path = ProcessInfo.processInfo.environment["PARHELION_README_IMAGES"] ?? ""
        let directory = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for screen in AppearanceGallery.Screen.allCases {
            try AppearanceGallery.readmeImage(screen).write(
                to: AppearanceGallery.readmeImageURL(screen, in: directory))
        }
    }
}
