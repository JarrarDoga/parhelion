# Changelog

All notable changes to Parhelion are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0, minor versions
may contain breaking changes.

## [Unreleased]

### Added

- `ParhelionUI`, a headless implementation of the SwiftUI view model: `View`, `ViewBuilder`,
  `Text`, `Image`, `Button`, `VStack`, `HStack`, `ZStack`, `Spacer`, `Color`, and `EmptyView`.
- `@State` and `@Binding`, with storage keyed by structural identity.
- The `padding`, `foregroundStyle`, and `imageScale` modifiers.
- `App`, `Scene`, and `WindowGroup`, with a headless runner that prints the view tree.
- `ViewHost`, which resolves a view to a `Codable` `ViewNode` tree and delivers taps.
- A `SwiftUI` module on Linux, so unmodified `import SwiftUI` sources compile against Parhelion.
- A layout pass that assigns every node a frame, following SwiftUI's propose-and-respond model,
  with SwiftUI's stack algorithm.
- Text measurement and wrapping with the bundled Inter typeface.
- The `frame(width:height:alignment:)` and
  `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` modifiers,
  and `padding(_:)` with `EdgeInsets`.
- `Device`, with an iPhone 16 preset, and `ViewHost(_:device:)`.
- `ViewHost.tap(at:)`, which taps the frontmost button at a screen position.
- `ViewNode.frame` and `ViewNode.modifiers`, which list layout modifiers in the order they apply.
- `--frames` for the headless app runner.
- `ParhelionRender`, a pure-Swift renderer: TrueType outlines, anti-aliased path filling, and PNG
  encoding, with no dependencies.
- `ViewHost.render(scale:)`, which draws the tree into a `RenderedFrame`, and `--png PATH` for the
  app runner.
- The `background(_:ignoresSafeAreaEdges:)` modifier with a shape style, and
  `ViewNode.modifierFrames`.
- iOS's light-appearance system colors for named colors and styles.
- A `Counter` example.
- The `parhelion` command-line tool, in `Tools/parhelion-cli`, with `parhelion preview`: an SDL3
  window that shows an app's frames and sends mouse input back.
- `ParhelionPreview`, the socket protocol between an app and the window host. Apps run a preview
  session automatically when the window host starts them.
- `ViewHost.pointerDown(at:)`, `pointerMoved(to:)`, `pointerUp(at:)`, and `pressedNodeID`, with
  iOS's press, cancel, and release behavior. Pressed buttons draw dimmed.
- `parhelion run`, with hot reload: it rebuilds on save, restarts the app in the same window, and
  keeps `Codable` `@State` values. It runs executable products and `xtool`-shaped library apps.
- `ViewHost.stateSnapshot()` and `ViewHost(_:device:restoring:)`.
- `ScrollView` and `ForEach`, with scrolling by drag with momentum, by mouse wheel, and by
  trackpad. `ViewHost.scroll(by:at:)`, `scroll(_:to:)`, `scrollOffset(of:)`, `isAnimating`, and a
  deterministic clock, `advanceTime(by:)`.
- `ViewHost.revision`, which increases whenever the screen changes.
- `parhelion run --configuration release`.
- A `Scrolling` example.
- `TextField(_:text:)`, with focus by click or Tab, typing, Backspace, Delete, the caret keys,
  Home, and End. `ViewHost.focus(_:)`, `typeText(_:)`, `press(_:)`, `focusedNodeID`, and
  `caretOffset`, and keyboard input in the preview window.
- `Color.opacity(_:)`.
- A `Form` example.
- `parhelion mcp`, a Model Context Protocol server for coding agents. Its tools read the view tree,
  take screenshots, tap, type, press keys, scroll, drag, wait, rebuild, and read the app's
  output. `--window` shows the same app in a preview window.
- `ViewHost.execute(_:)` and `drag(from:to:duration:)`, and command and reply messages in the
  preview protocol.
- `List` and `Section`, with headers, footers, and the inset grouped, grouped, and plain styles
  through `listStyle(_:)`. Lists scroll, separate their rows, and make a button row respond to
  taps across its whole width. Rows record a `listRow` layout modifier with their cell's bounds.
- A `Tasks` example.
- `NavigationStack`, with a path binding of one type or a `NavigationPath`, and `NavigationLink`
  with a destination view or a value. The navigation bar shows the top view's
  `navigationTitle(_:)`, a back button labeled with the previous title, and items from
  `toolbar(content:)` with `ToolbarItem` and `ToolbarItemGroup`. Also
  `navigationDestination(for:destination:)`, `navigationBarBackButtonHidden(_:)`,
  `navigationBarTitleDisplayMode(_:)`, and `NavigationView`. Titles display inline.
- In a list, a navigation link's row shows a disclosure indicator.
- `Image(systemName:)` draws chevrons for `chevron.backward`, `chevron.left`, `chevron.forward`,
  and `chevron.right`.
- `ViewHost.tapButton(labeled:)` also taps navigation links.

### Changed

- Rectangles render through a fast path, so a full frame takes about 7 ms in a debug build
  instead of 45 ms.
- Build errors from `parhelion run` are plain text, without the compiler's color codes.

### Fixed

- The first click on an unfocused preview window reaches the app. Before, SDL used the click only
  to focus the window.

[Unreleased]: https://github.com/JarrarDoga/parhelion/commits/main
