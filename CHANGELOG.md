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
- `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)`, and the matching
  `fullScreenCover` modifiers, with `presentationDetents(_:)`. Drag a sheet down to dismiss it.
- `alert(_:isPresented:actions:)` and `alert(_:isPresented:actions:message:)`, with and without
  `presenting:` data. Every action dismisses the alert after it runs.
- `ButtonRole`, with `Button(_:role:action:)` and `Button(role:action:label:)`. Destructive
  buttons are red.
- `@Environment`, `EnvironmentKey`, `EnvironmentValues`, and `environment(_:_:)`, with the
  `dismiss` and `isPresented` values. `dismiss` closes a sheet or pops a pushed view.
- `ViewHost.interactiveRoot`, the frontmost sheet or alert, and `InteractionError.covered` for
  a tap on a view behind one.
- Animation: `withAnimation(_:_:)`, `animation(_:value:)`, and `Animation` with `default`,
  `linear`, `easeIn`, `easeOut`, `easeInOut`, `timingCurve`, `spring`, `interactiveSpring`,
  `smooth`, `snappy`, `bouncy`, `delay(_:)`, and `speed(_:)`. Animations run on the host's clock.
- `transition(_:)` with `AnyTransition`: `opacity`, `identity`, `slide`, `move(edge:)`,
  `offset`, `push(from:)`, `asymmetric(insertion:removal:)`, and `combined(with:)`.
- Navigation pushes and pops slide the screens, and sheets and alerts animate in and out.
- The `opacity(_:)` and `offset(x:y:)` modifiers.
- `ViewHost.presentedRoot`, the tree as drawn while animations run. `root` keeps final values
  (see ADR 0005).
- Not yet supported: `scaleEffect`, `rotationEffect`, `matchedGeometryEffect`, the `scale`
  transition, color interpolation, and repeating animations.
- Device chrome: `ViewHost.render(scale:chrome:)` draws the iOS 27 status bar (the clock, signal,
  Wi-Fi, and a full battery) and the home indicator with `.systemBars`, and adds the Dynamic Island
  or notch and the screen's rounded corners with `.screen`.
- The preview window shows the screen inside a phone bezel with side buttons, like the iOS
  Simulator, in a window that is transparent outside the phone. `--no-bezel` shows the screen
  alone.
- iPhone presets in `Device.all`, found by name with `Device.named(_:)`, and `--device` for
  `parhelion run`, `parhelion preview`, and `parhelion mcp`. Apps read the device from
  `PARHELION_DEVICE`.
- `Device.displayCornerRadius`, `Device.sensorHousing`, and `Device.homeIndicatorWidth`.
- Inter SemiBold, for the status bar's clock, and `TrueTypeFont.capHeight`.
- `CanvasOverlay`, a drawing kept to blend over many canvases, `Canvas.fill(_:clippedTo:color:)`,
  and `Path(roundedRect:cornerRadius:reversed:)` in `ParhelionRender`.
- `parhelion mcp` includes the app's last output when the app exits before it connects.
- `Font`, with the text styles from `largeTitle` to `caption2`, `system(size:weight:design:)`,
  `system(_:design:weight:)`, `Font.Weight`, `Font.Design`, `weight(_:)`, and `bold()`; the
  `font(_:)`, `fontWeight(_:)`, and `bold(_:)` modifiers and `EnvironmentValues.font`; and
  `Text.font(_:)`, `Text.fontWeight(_:)`, and `Text.bold(_:)`. A `Text` node records a font other
  than the body style as an attribute, such as `font=headline`, and layout and drawing use its
  size, line height, and weight. Every design draws with Inter.
- Inter Medium and Inter Bold, as `TrueTypeFont.interMedium` and `TrueTypeFont.interBold`. Text
  draws with the bundled weight nearest to its font's weight.
- Large navigation titles: the root of a `NavigationStack` shows its title in bold 34-point type
  below the bar's row of buttons, and pushed views inherit the display mode of the view beneath.
  `navigationBarTitleDisplayMode(_:)` now chooses `.large` or `.inline`, and the `NavigationBar`
  node records a `titleDisplayMode` attribute.

### Changed

- Screenshots from `parhelion mcp` and `--png` images show the status bar and the home indicator,
  as Simulator screenshots do.

- Rectangles render through a fast path, so a full frame takes about 7 ms in a debug build
  instead of 45 ms.
- Build errors from `parhelion run` are plain text, without the compiler's color codes.
- A child outside its parent's bounds, such as a view moved by `offset`, receives taps, except
  inside a scroll view.
- Rounded rectangles fill their interiors as rectangles and rasterize only their corners, and a
  translucent fill blends once for each run of equal pixels. A screen with a sheet renders in
  16 ms in a debug build instead of 380 ms.
- Each line of text is as tall as its text style's line height: 22 points for body text instead
  of Inter's own 20.57.
- The navigation bar follows the iOS 27 UI Kit: 54 points tall with an inline title, which is
  semibold, and 105 points with a large title. Its buttons and inline title center in the top
  44 points instead of the whole bar.
- Named colors use iOS 27's values: blue, the default tint, is 0,136,255 instead of 0,122,255,
  and red, orange, mint, teal, cyan, indigo, purple, and brown changed too. List separators are
  black at 12% opacity.

### Fixed

- The first click on an unfocused preview window reaches the app. Before, SDL used the click only
  to focus the window.

[Unreleased]: https://github.com/JarrarDoga/parhelion/commits/main
