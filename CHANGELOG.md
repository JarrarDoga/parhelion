# Changelog

All notable changes to Parhelion are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0, minor versions
may contain breaking changes.

## [Unreleased]

### Added

- `Scripts/run-on-iphone.sh EXAMPLE` builds an example for iOS with Apple's SwiftUI, installs it on a connected iPhone with xtool, and starts it.
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
  `navigationBarTitleDisplayMode(_:)`, and `NavigationView`.
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
- Drawing primitives in `ParhelionRender` for Liquid Glass, which views do not use yet:
  - `Path.addCurve(to:control1:control2:)`, for cubic curves.
  - `Path.CornerStyle` and `Path(roundedRect:cornerRadius:style:reversed:)`. `.continuous`
    approximates iOS's continuous corners and blends to circular corners on short sides, so half
    the height still makes a capsule. `Canvas.fill(_:cornerRadius:style:color:)` fills them
    quickly.
  - `Canvas.drawShadow(of:color:offset:blur:drawsUnderShape:)` for paths and rounded rectangles:
    blurred drop shadows, cut away under the shape unless `drawsUnderShape` is set.
  - `Path.StrokeAlignment`, `Path(ringAround:cornerRadius:style:lineWidth:alignment:)`, and
    `Canvas.stroke(_:cornerRadius:style:lineWidth:alignment:color:)`: rings inside, centered on,
    or outside a rounded rectangle's edge.
  - `Canvas.LinearGradient` and `Canvas.fill(_:gradient:)`: linear gradients at any angle, with
    any number of stops, for paths and rectangles.
  - `Canvas.BlendMode` and `Canvas.blendMode`: `normal`, `multiply`, `screen`, `lighten`, `darken`,
    `plusLighter`, and `plusDarker`.
  - `Canvas.blur(_:cornerRadius:style:radius:saturation:)`: blurs the pixels inside a rounded
    rectangle and scales their saturation.
- Preview protocol capabilities: an app lists `hostClock` and `sharedFrames` in its hello, and a
  window host that supports them answers with `welcome`. Older apps and hosts keep working with
  newer ones (see ADR 0006).
- `PreviewTick`, `PreviewFrameUpdate`, `PreviewSharedMemory`, `SharedFrameBuffer`, `SlotPool`,
  `PreviewClock`, and `PreviewTimeline` in `ParhelionPreview`.
- `parhelion run` prints its build mode, the modules each rebuild compiled, and the time from a
  change to the new app's first frame, split into build and restart.
- Button styles: `buttonStyle(_:)` with `.automatic`, `.plain`, `.borderless`, `.bordered`,
  `.borderedProminent`, `.glass`, and `.glassProminent`, and custom `ButtonStyle` types, whose
  `makeBody(configuration:)` replaces the label. Bordered and glass buttons are capsules 34
  points tall with 12 points of padding; `controlSize(_:)` makes them smaller or larger. A button
  records its style as a `buttonStyle` attribute.
- `tint(_:)`, which colors buttons' labels and prominent buttons' fills.
- `presentationDragIndicator(_:)` and `Visibility`. A sheet with several detents, or one that asks
  for it, shows a grabber.
- `ViewNode.label` returns a node's `label` attribute when it has one.
- `Device.maximumFramesPerSecond`, like UIKit's `UIScreen.maximumFramesPerSecond`: 120 for the
  presets with ProMotion and 60 for iPhone 16, 16 Plus, and 16e. The preview window shows the app's
  animations no faster than its device: on a 240 Hz display, each frame of a 120 Hz iPhone stays
  up for two refreshes.
- `PARHELION_REFRESH_RATE`, which makes the window host assume a display refresh rate, for testing
  frame pacing on a display without real vsync.
- iPhone 18 Pro and iPhone 18 Pro Max presets, with their smaller Dynamic Island.
- `tag(_:includeOptional:)`, which identifies a view among a container's choices and records a
  `tag` attribute. Inside such a container, the views of a `ForEach` element are tagged with the
  element's identifier.
- `TabView`, with `selection:`, `Tab` (with a title and a symbol, a value, a role, or a custom
  label), `Tab(role: .search)`, `TabRole`, `TabContent`, `TabContentBuilder`, and the older
  `tabItem(_:)` with `tag(_:)`. Only the selected tab is on screen, and every tab keeps its state and its
  navigation stack while another is selected. A tab view without a binding keeps its own
  selection.
- iOS 27's floating glass tab bar, from the iOS 27 UI Kit: a 62-point capsule 21 points from the
  sides and the bottom of the screen, below the safe area, with a gray highlight behind the
  selected tab, its symbol and title in the tint color, and the search tab in a circle of its own.
  Each tab is a `Button` node, so taps by identifier, by title, by position, and with the mouse
  select it. Lists and scroll views in a tab scroll under the bar and can scroll their end above
  it.
- `Label`, with `labelStyle(_:)`: `.automatic`, `.titleAndIcon`, `.titleOnly`, `.iconOnly`, and
  custom `LabelStyle` types. In a toolbar, a label shows only its icon.
- Symbol images drawn with [Phosphor Icons](https://phosphoricons.com) (MIT): 246 SF Symbol names,
  listed in `Symbols/symbols.txt`, map to 245 Phosphor icons, in Phosphor's fill weight for names
  that end in `.fill`. `Scripts/embed-symbols.sh` generates their SVG path data into source. A
  name Parhelion cannot draw is a ring, and its node records `missingSymbol=true`.
- `Path(svgPathData:)` in `ParhelionRender`, which reads SVG path data, including arcs.
- `EnvironmentValues.imageScale`.
- A `Tabs` example with three tabs and a search tab, shown in the README.
- `Toggle`, drawn as iOS 27's 64 × 28 switch at the trailing edge of its row. The `Switch` node
  responds to taps and carries the toggle's label, and its knob slides with a spring while
  content that depends on the value changes at once. `toggleStyle(_:)` accepts `.automatic` and
  `.switch`.
- `LabeledContent`, with its content at the trailing edge in the secondary color, `Divider`, and
  `Form`, which is an inset grouped list. A row that holds a switch stays 52 points tall.
- `disabled(_:)` and `EnvironmentValues.isEnabled`. Disabled buttons, links, text fields, and
  controls record `disabled=true`, draw dimmed, and do not respond to input.
- `Stepper`, with a value and bounds or with actions: a 92 × 32 capsule whose halves are
  `StepperButton` nodes labeled `Decrement` and `Increment`. A half turns off at the end of the
  range.
- `Slider`, with bounds, steps, a label, value labels, and `onEditingChanged`. The node records
  `value`, `bounds`, `step`, and `label`. A press on the track drags the knob, which becomes a
  glass lens; a tap on the track moves the knob there. `tap(at:)`, the pointer methods, and
  `parhelion mcp`'s tap and drag all drive it, and a drag on a slider in a list does not scroll.
- `Picker`, with `pickerStyle(_:)` and the `.segmented`, `.menu`, `.inline`, `.navigationLink`,
  and `.automatic` styles. Options are tagged views or `ForEach` elements, and each is a
  `PickerOption` that responds to taps and to its label. A segmented picker is the iOS 27 UI
  Kit's 32-point capsule, whose white selection slides. A menu picker, which `.automatic` is,
  shows its value and up and down chevrons, and opens iOS 27's 250-point glass `Menu` at the root
  of the tree, which a tap outside closes. An inline picker in a list is a section of rows with a
  checkmark, under its label; a navigation-link picker pushes the options and goes back when one
  is chosen. The node records `pickerStyle` and `selection`.
- The `Settings` example, a form with each control: `swift run Settings`, or
  `parhelion run --product Settings`.
- `--web` for `parhelion run`, `parhelion preview`, and `parhelion mcp`: the preview as a web page,
  at a URL the tool prints, for any browser on a desktop or a phone. The page shows the screen in
  the phone bezel, scaled to the window, and sends taps, drags, wheel and trackpad scrolling, and
  typing back. It stays connected across hot reloads and shows build errors. The server binds
  127.0.0.1 unless `--web-address` names another address, such as a Tailscale address or
  `0.0.0.0`; `--web-port` picks the port (8417 by default). Every request needs the random token
  in the printed URL. `--web` needs no display, and with `parhelion mcp --window` the window and
  the page show the same app.
- `@Observable` models, through the Swift toolchain's Observation module: each update records the
  observable properties that views read with `withObservationTracking`, and a change to any of
  them updates the tree. `import SwiftUI` alone makes `@Observable` and Foundation's types
  available, as on Apple platforms.
- `@Bindable`; `Binding`'s dynamic members, such as `$model.name`; `Binding(projectedValue:)`;
  `Binding`'s `Identifiable`, `Collection`, and related conformances; and `ForEach(_:content:)`
  and `ForEach(_:id:content:)` for bindings, so that `ForEach($items) { $item in ... }` works.
- `environment(_:)` with an observable object, read with `@Environment(Model.self)` or as an
  optional.
- `Group` and `AnyView`.
- `onAppear(perform:)`, `onDisappear(perform:)`, `onChange(of:initial:_:)`, and `task` with and
  without an `id`. A view appears when one of its nodes enters the tree, so a screen that a
  navigation push covers disappears. Tasks run on the main actor, `ViewHost.pendingTaskCount`
  counts them until they return, even after they are cancelled, and `ViewHost.waitForTasks()`
  waits for them.
- The `colorScheme`, `dynamicTypeSize`, `horizontalSizeClass`, `verticalSizeClass`, and `locale`
  environment values, with `ColorScheme`, `DynamicTypeSize`, and `UserInterfaceSizeClass`. They
  describe an iPhone in portrait in the light appearance and US English.
- A `Library` example that keeps an `@Observable` model in the app's `@State`, edits it through
  `ForEach($library.books)` and `@Bindable`, and loads it in `task`.
- `parhelion mcp` reports `task` work that is still running, and its `wait` tool returns as soon
  as animations and that work finish. `PreviewReply.pendingTasks` carries the count.
- Shapes: the `Shape` protocol, `Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, `Capsule`,
  and `Path` as a view, with `fill(_:style:)`, `fill(style:)`, and `FillStyle`'s even-odd rule.
  `RoundedRectangle` and `Capsule` have continuous corners by default, as in iOS 27. A shape of
  an app's own type draws the path it returns for its frame, and its node records its
  description as `shape`. `Path` gains `init(_:)`, `addRect(_:)`, `addRects(_:)`,
  `addRoundedRect(in:cornerSize:style:)`, `addEllipse(in:)`, `addLines(_:)`,
  `addArc(center:radius:startAngle:endAngle:clockwise:)`, and `currentPoint`, with `Angle`.
- `LinearGradient` as a view and as a shape style, with `Gradient`, `Gradient.Stop`, `UnitPoint`,
  and `.linearGradient(_:startPoint:endPoint:)` and its `colors:` and `stops:` forms. A gradient
  fills each shape or background it paints, and the tree records it as
  `linearGradient(red 0, blue 1, top, bottom)`. `ForegroundStyle` and `.foreground` name the
  current foreground style.
- `overlay(alignment:content:)`, whose views become an `Overlay` node, the last child of the view
  they cover, placed in the bounds at the modifier's place in the chain; `overlay(_:in:fillStyle:)`
  and `overlay(_:ignoresSafeAreaEdges:)`; `clipShape(_:style:)`, `clipped(antialiased:)`, and
  `cornerRadius(_:antialiased:)`, deprecated in iOS 27.2 as in SwiftUI; `shadow(color:radius:x:y:)`,
  a blurred shadow of everything the view draws; and `scaleEffect` with an anchor, which mirrors
  the view at a negative scale. None of them changes layout, and each applies at its place in the
  modifier chain: a clip clips the backgrounds inside it and not those outside.
- `LazyVGrid`, `LazyHGrid`, and `GridItem` with `.fixed`, `.flexible`, and `.adaptive` sizes:
  fixed items and spacing come first, flexible and adaptive items share the rest within their
  bounds, and an adaptive item holds as many columns of its minimum as fit. Parhelion evaluates
  every cell, and accepts `PinnedScrollableViews` without pinning anything yet.
- `Grid` and `GridRow`, with `gridCellColumns(_:)`, `gridColumnAlignment(_:)`,
  `gridCellUnsizedAxes(_:)`, and `gridCellAnchor(_:)`. Columns are as wide as their widest cell
  and rows as tall as their tallest; columns and rows with flexible cells share the space left,
  and a view outside a `GridRow` spans every column. The default spacing is 8 points.
- Images from asset catalogs: `Image(_:bundle:)`, `resizable(capInsets:resizingMode:)` with
  `.stretch` and `.tile`, and `renderingMode(_:)` with `.template` and `.original`. On Linux,
  SwiftPM copies an app target's `Assets.xcassets` unprocessed into the target's resource bundle,
  so Parhelion reads the catalog there: image sets in groups and namespaces, 1×, 2×, and 3× files,
  dark appearances, and `template-rendering-intent`. Without a bundle, it looks in the main
  bundle and every bundle beside it. The renderer draws the file for its scale, and the dark one
  when `colorScheme` is dark. An image's node records `name`, `bundle`, `size`, `appearance`,
  `renderingMode`, `resizable`, `capInsets`, and `resizingMode`. A missing image, or one that is
  not a PNG image, records `missingImage=true` and draws as a ring, as a missing symbol does.
- A resizable symbol image fills its frame, and symbols take gradient foreground styles.
- `AsyncImage` with all three initializer families for a URL and for a `URLRequest`,
  `AsyncImagePhase`, `Transaction`, and `asyncImageURLSession(_:)`. The load is a `task` of the
  view, so `ViewHost.waitForTasks()` waits for it and `parhelion mcp` counts it in
  `pendingTasks`. It reads `file:` URLs from disk and others with `URLSession`, decodes PNG
  images, and fails on anything else. Until the image loads, `AsyncImage(url:scale:)` shows a
  gray `secondarySystemFill` rectangle. Its node records `url`, `phase`, and `scale`.
- `aspectRatio(_:contentMode:)`, `scaledToFit()`, and `scaledToFill()`, with `ContentMode`.
- `import SwiftUI` re-exports FoundationNetworking on Linux, where `URLRequest` and `URLSession`
  live, as Apple's SwiftUI makes them available through Foundation.
- `ParhelionRender` decodes PNG images in pure Swift (`Bitmap(pngData:)`), with every color type
  and bit depth, transparency, all five filters, and Adam7 interlacing, through its own inflate.
- The `xtool`-shaped `LibraryApp` fixture shows an image from its own `Assets.xcassets`.
- README images of shapes, gradients, the styling modifiers, images, `AsyncImage`, and grids,
  written by `PARHELION_README_IMAGES=docs/images swift test --filter writeContentReadmeImages`
  and checked against a fresh render by `swift test`.
- `Scripts/check-ios-build.sh` builds shapes, gradients, the styling modifiers, images,
  `AsyncImage`, and grids against Apple's SwiftUI, then reports whether xtool builds the app with
  an asset catalog. xtool 1.22.2 does not: SwiftPM runs `actool` from xtool's temporary folder,
  where xtool puts none.
- ADR 0010: images come from the app's raw asset catalog, decoded in pure Swift, through a side
  table.
- `ParhelionRender` clips drawing to any path (`Canvas.beginClip(to:evenOdd:)` and
  `endClip(_:)`), draws and shadows layers (`draw(layer:atPixelX:y:flipX:flipY:)` and
  `drawShadow(ofLayer:atPixelX:y:color:offset:blur:)`), draws `Bitmap` images scaled with bilinear
  sampling, fills paths with the even-odd rule, and writes a path as SVG path data.

- Dark mode. `ViewHost.colorScheme` sets the simulated device's appearance, and
  `preferredColorScheme(_:)` sets the preferred color scheme of the window or the sheet that
  contains it, as SwiftUI does: the whole presentation takes it, an outer modifier wins over an
  inner one, and the first of two siblings wins. `environment(\.colorScheme, _:)` changes the
  scheme of its content. Nodes record `colorScheme=dark` where the scheme changes, and the root
  records it while the window is dark.
- iOS 27's dark appearance, from the dark swatches and components of Apple's iOS 27 UI Kit: the
  dark system colors and labels, black screens with 28-gray grouped cells, lighter backgrounds in
  sheets, dark Liquid Glass for toolbar buttons, the tab bar, alerts, menus, and partial-height
  sheets, the dark variants of switches, sliders, steppers, and segmented controls, and a white
  status bar and home indicator.
- A `luminosity` blend mode in `ParhelionRender`, which dark Liquid Glass uses.
- Dynamic Type. `ViewHost.dynamicTypeSize` sets the simulated device's text size, and text
  styles take their size and line height from the iOS 27 UI Kit's Dynamic Type table, from
  `xSmall` to `accessibility5`. A `Text` whose size differs from its style's size at Large
  records `fontSize`, and nodes record `dynamicTypeSize` where it changes.
- `dynamicTypeSize(_:)` with a size or a range, which limit each other as SwiftUI documents,
  `@ScaledMetric`, and `Font.custom(_:size:)`, `Font.custom(_:size:relativeTo:)`, and
  `Font.custom(_:fixedSize:)`, drawn with Inter.
- List rows, list footers, large navigation titles and their bar, bordered buttons, alert
  buttons, text fields, and symbols grow with Dynamic Type. Toolbar items, the tab bar, and segmented controls
  keep their size, as on iOS.
- Control-Shift-A in the preview window switches between light and dark, and Control-Alt-Plus
  and Control-Alt-Minus change the text size. The window's title shows the setting.
- A Light or Dark button and a text size menu on the `--web` page.
- The `set_appearance` tool in `parhelion mcp`.
- `PARHELION_COLOR_SCHEME` and `PARHELION_DYNAMIC_TYPE_SIZE`, which start an app in an appearance
  and a text size, with or without `--png`. The tool passes the current setting to every launch,
  so it survives hot reload and `rebuild`.
- `PreviewCommand.setAppearance(colorScheme:dynamicTypeSize:)` and the `appearance` capability in
  the preview protocol.
- README images of the dark appearance and of large text sizes.
- Extension points: a view kind, a layout modifier, a render effect, an MCP tool, or a window
  hook now plugs in from its own file, so later changes do not edit the layout engine, the
  renderer, `AgentTools.swift`, or `WindowHost.swift`. See ADR 0011.
- `ViewHost.longPress(at:duration:)` and `ViewHost.drag(from:to:duration:)`, which reach views by
  hit testing. `drag` is now public and sends a drag to the view under its start, or moves the
  pointer there as before.


- `parhelion run` and `parhelion mcp` build apps that link a native library, such as a Rust core
  with UniFFI bindings. A `parhelion.json` in the app's package, or the options `--pre-build`,
  `--watch`, and `--library-path`, name a command that runs before every `swift build`, more
  files and directories whose changes rebuild the app, and directories with prebuilt libraries.
  Errors from the command reach `parhelion mcp` like Swift errors. The runner package keeps a
  target's linker settings.

- `--jobs` for `parhelion mcp` and the `PARHELION_BUILD_JOBS` environment variable, which limit the
  jobs of `swift build`, so many sessions can share one machine. The README states the memory one
  session needs and how many to run at once, and `Scripts/measure-mcp-sessions.py` measures it.

- The `compare_image` tool in `parhelion mcp`, which renders the screen at a design board's scale
  and returns the share of pixels that differ, within a tolerance, the area they lie in, and a
  diff PNG with them in red; `ImageDiff` and `BoardComparison` in `ParhelionTooling`, which
  snapshot tests can use; and `Bitmap.pngData()`.
- `parhelion run --overlay board.png --overlay-opacity 0.5`, which draws a design board over the
  preview window.

- `accessibilityIdentifier(_:)`, `accessibilityLabel(_:)`, and `accessibilityElement(children:)`,
  recorded in the view tree. An identifier on a container reaches the views inside it, as in
  SwiftUI. `tapButton(labeled:)` and the `tap` tool match accessibility labels. `ViewHost` taps,
  focuses, and scrolls by identifier, and the `tap`, `type_text`, and `scroll_to` tools of
  `parhelion mcp` take `accessibility_identifier`, so an agent's script survives layout changes.

- A manual clock for agents: in `parhelion mcp` without `--window` or `--web`, `wait` advances the
  app's time instead of sleeping, so animations, scroll momentum, and `Task.sleep` in `task`
  actions, `Task`s, and detached tasks reach the state they would after that long, in milliseconds.
  The app starts with `PARHELION_MANUAL_CLOCK=1`, lists the `manualClock` capability, and takes
  the `advanceTime(seconds:)` command; its replies carry `nextWake`. It needs Swift 6.3 or later;
  with a window or a page, `wait` keeps real time. See ADR 0012.

- Snapshot tests: `ViewHost.expectSnapshot(named:scale:chrome:channelTolerance:pixelTolerance:)`
  in the new `ParhelionTesting` library compares a render with a PNG in `Tests/__Snapshots__/` and
  records a Swift Testing issue with the actual and the difference image attached.
  `PARHELION_RECORD_SNAPSHOTS` (`missing`, `failed`, `all`, `never`) chooses whether references are
  written; CI uses `never`. `Bitmap.difference(from:channelTolerance:)` and `differenceImage(from:)`
  in `ParhelionRender` give the pixel counts. The README image tests use them, in place of
  `PARHELION_README_IMAGES`, for the Tasks and Tabs images.

- Placeholder for #32 (build, install and run on the iPhone): the change for that issue replaces this line.

- Your own SF Symbols in front of Phosphor: `parhelion symbols import` copies SVG exports from the SF Symbols app into `~/.local/share/parhelion/symbols`, or `PARHELION_SF_SYMBOLS` names a folder of exports. `Image(systemName:)` draws them at the font's weight, and the tree records `symbolSource=sfSymbols`. Parhelion still ships none, and `Scripts/check-no-sf-symbols.sh` fails CI if Apple's symbol data is committed.

- `LazyVStack` and `LazyHStack` with `pinnedViews`, and lazy rows in `List`: inside a scroll view they
  evaluate only the rows on screen and a margin, keep the `@State` of rows that scrolled out by
  identity, and run `onAppear` as a row is created, so a 5,000-row list scrolls at 120 Hz.
  `scroll_to` reaches rows that do not exist yet. A node records `lazyCount` and `lazyResolved`
  while it holds only some of its rows.

- Gestures: `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, and `DragGesture` with `onChanged`, `onEnded`, and `updating` with `@GestureState`; `simultaneously`, `sequenced`, and `exclusively`; and the `onTapGesture`, `onLongPressGesture`, `gesture`, `simultaneousGesture`, and `highPriorityGesture` modifiers. A drag follows the pointer one to one, a long press fires after its minimum duration on the host's clock, and buttons, gestures, and scroll views resolve conflicts as SwiftUI does (see ADR 0015). The `long_press` MCP tool holds a press at a point; `drag` already took a duration.

- `glassEffect(_:in:isEnabled:)` draws Liquid Glass, `.regular`, `.clear`, `.tint(_:)`, and `.interactive()`, in any shape.
  `GlassEffectContainer(spacing:)` draws the glass of its views as one piece where shapes come closer than the spacing,
  and `glassEffectID(_:in:)` makes glass that appears or disappears in an animation grow out of, or shrink into, the glass
  beside it. `@Namespace` now keeps its ID across updates.

- `Menu` opens a glass menu of buttons, sections, dividers, destructive items, and a `ControlGroup` row of icon-over-title buttons, from a tap or, with a `primaryAction`, a long press. `contextMenu(menuItems:)` and `contextMenu(menuItems:preview:)` open the same menu on a long press (`ViewHost.longPress(at:duration:)` or the `long_press` MCP tool): the screen behind blurs and the view lifts to 1.03.

- `ScrollViewReader` and `ScrollViewProxy.scrollTo(_:anchor:)`, `id(_:)` with identity, `scrollPosition(id:anchor:)` and `scrollPosition(_:anchor:)` in both directions with `ScrollPosition` (including its `idType:` initializers), `scrollTargetLayout()`, `scrollTargetBehavior(.paging)` and `.viewAligned`, and `onScrollGeometryChange(for:of:action:)`, which scroll, settle, and report the geometry of `ScrollView` and `List`; `ViewHost.scroll(toViewID:anchor:)` and `scrollPositionID(of:anchor:)` for tests and tools. They reach rows of lazy stacks and lists that do not exist yet.

- `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` work in a preview: the app's now-playing
  info (title, artist, album, duration, elapsed time, playback state) and its enabled commands
  go to the window host, which publishes an MPRIS player on the session bus, so the KDE media
  widget and `playerctl` show the title and position. `playerctl` play, pause, play-pause, stop,
  next, previous, seek, and position reach the targets the app added. The host speaks D-Bus
  itself, in pure Swift, so apps and the tool link no D-Bus library; without a session bus, the
  preview works as before. The protocol gains `PreviewCapability.mediaSession`,
  `AppMessage.nowPlaying`, and `HostMessage.remoteCommand`, and `PreviewChannel` locks its
  sends so that any thread can send. See ADR 0017.

- Text selection, copy, cut, and paste in `TextField`, and `PasteButton(payloadType:onPaste:)`.
  Drag over a field, or use Shift with the arrow keys, Home, and End, to select; Control-A selects
  all, Control-C and Control-X copy and cut, and Control-V pastes, through the window's clipboard.
  Typing, Backspace, and Delete replace the selection, which draws as a tint highlight.
  `ViewHost.selectedRange`, `selectedText`, `select(_:)`, `pasteboardText`, and the keys
  `selectLeft`, `selectRight`, `selectHome`, `selectEnd`, `selectAll`, `copy`, `cut`, and `paste`
  (also for `press_key`). `PasteButton` pastes the pasteboard as a `String`, a `URL`, or `Data`,
  and is disabled while the pasteboard has nothing of its type. The `set_clipboard` MCP tool and
  `PreviewCommand.setPasteboard` fill the pasteboard for agents; the `pasteboard` capability keeps
  the app's pasteboard in step with the window's system clipboard.

- `matchedGeometryEffect(id:in:properties:anchor:isSource:)` makes a view that arrives in an animation start at the frame
  of the view with the same ID and namespace, and the view it replaces moves to the new frame as it fades out.
  `matchedTransitionSource(id:in:)` and `navigationTransition(.zoom(sourceID:in:))` make a `fullScreenCover` or a pushed
  screen grow out of the source's frame and shrink back into it. A matched view that is inside a view that leaves fades
  out where it was instead of moving, and `isSource` only decides which view is the starting point.

- `tabViewBottomAccessory` draws its content in a glass capsule above the tab bar, `tabViewBottomAccessoryPlacement` is `.expanded` there and `.inline` beside a minimized bar, and `tabBarMinimizeBehavior(.onScrollDown)` or `.onScrollUp` shrinks the bar to a small capsule while the content scrolls, with an animation. A tap on the small capsule brings the bar back.

- `swipeActions(edge:allowsFullSwipe:content:)` on `List` rows, on both edges, drawn after iOS 26:
  dragging a row sideways with the pointer, or `ViewHost.drag`, moves it inside its cell and
  reveals tinted action buttons, which a tap runs. Letting go past half the actions, or flinging,
  leaves the row open; a full swipe runs the first action. Tapping elsewhere closes an open row.
  Rows record `swipeActions` and, while moved, `swipeOffset`. See the architecture document.

- `onMove(perform:)` and `onDelete(perform:)` on `ForEach`, `EditButton`, `moveDisabled(_:)`, and `deleteDisabled(_:)` now work. In a `List` whose `editMode` environment value is active, each row shows a delete button for `onDelete` and a reorder handle for `onMove`; dragging a handle onto another row calls the move action. Tapping the delete button shows Delete, as on iOS. Parhelion does not supply an edit mode of its own: set one with `environment(\.editMode, $mode)`.

- `searchable(text:placement:prompt:)` adds a search field and binds its text. In a tab with the search role it is a glass
  capsule at the bottom, above the tab bar; elsewhere, in a navigation stack or a sheet, it is a capsule under the
  navigation bar with a Cancel button while the user searches. Focus it, then `type_text` writes the binding.
  `isSearching` is true in the content while the field is focused or holds text, and `dismissSearch` ends the search.

- `rotationEffect(_:anchor:)`, `blur(radius:opaque:)`, and `mask(alignment:_:)` draw rotated, blurred, and masked
  views, in place of the compile-only stubs. A mask uses the alpha of its views, so a gradient fades a view out. None of
  them changes layout.

- `lineLimit(_:)` (a number, `nil`, a range, or `reservesSpace`) and `truncationMode(_:)` limit text to a number of lines
  and cut it off with an ellipsis at its tail, head, or middle, so a long song title fits a row. `TextField(_:text:axis:)`
  with `.vertical` wraps its text, grows from one line up to its line limit as text is typed, and scrolls past it; Return
  starts a new line. `ViewHost.Key` has `up` and `down`, which move the caret between lines, and the preview window, the web
  preview, and `press_key` send them.

- `listSectionIndexVisibility(_:)` and `sectionIndexLabel(_:)`: a list with labeled sections shows an A to Z index at its trailing edge, and tapping a letter or dragging over the letters scrolls the section with that label to the top.

- `sensoryFeedback(_:trigger:)` and its closure and condition forms record the feedback they would play, since
  Linux has no haptics. `ViewHost.sensoryFeedbackEvents` lists the last 50, the root of the view tree lists the newest
  ten in `sensoryFeedback`, `PARHELION_DEBUG=1` logs each one, and `parhelion mcp` returns them from the new
  `get_sensory_feedback` tool. `accessibilityReduceMotion` now reads `ViewHost.reduceMotion`, which the root shows as
  `reduceMotion=true`. Switch it with Control-Shift-M in the preview window, `set_appearance` with `reduce_motion` in
  `parhelion mcp`, `--reduce-motion` or `PARHELION_REDUCE_MOTION=1` on the command line, or the `setReduceMotion` preview
  command (capability `accessibilitySettings`).

- `refreshable(action:)` on a `List` or vertical `ScrollView`: dragging down from the top pulls the content
  away from iOS's spinner, and releasing past 60 points runs the action as a host task, so
  `waitForTasks()` waits for it, and holds the spinner until it returns. The `refresh` environment
  value runs the action. `ViewNode.isRefreshable` and `isRefreshing` report the state.

- `ProgressView` draws iOS 26's spinner (eight spokes, one turn a second) for an unknown amount, a
  ring for a known amount in `.circular`, and a 4-point bar for `value:total:` (such as "640 of
  1,535 songs"), with its label above the bar and its current value label below it.
  `progressViewStyle(_:)` with `.automatic`, `.circular`, `.linear`, `CircularProgressViewStyle(tint:)`,
  `LinearProgressViewStyle(tint:)`, and custom `ProgressViewStyle` types, which can wrap the
  default look with `ProgressView(configuration)`. A spinner and an
  indeterminate bar animate on the host's clock, so they follow `advanceTime(by:)` and a manual
  clock (#77).

- `scenePhase`: `@Environment(\.scenePhase)` in views and in an `App`, `Scene.onChange(of:initial:_:)`, and `ViewHost.scenePhase`, which the root records as `scenePhase=inactive` or `background`. The preview window sets `inactive` when it loses focus and `background` when it is minimized, and the `set_scene_phase` MCP tool moves the app between `active`, `inactive`, and `background`, so an agent can test what the app does on returning to the foreground.

- `AVFAudio` audio interruptions and route changes on Linux. `AVAudioSession` keeps its category, mode, options, and activity and does nothing else, now with `AVAudioSession.Port`, `InterruptionReason`, and a `currentRoute` (the speaker until a device is plugged in). The `audio_interruption` (began or ended, with `should_resume` and a reason) and `audio_route_change` (default: headphones, `oldDeviceUnavailable`) MCP tools, and `ViewHost.postAudioInterruptionBegan(reason:)`, `postAudioInterruptionEnded(shouldResume:)`, and `postAudioRouteChange(reason:device:)`, post `AVAudioSession.interruptionNotification` and `routeChangeNotification` with Apple's keys, so an app's handlers run (see ADR 0018). `AVAudioSessionPortDescription.portType` is now `AVAudioSession.Port`, as in Apple's SDK (#79).

- `TimelineView` with the `periodic(from:by:)`, `everyMinute`, `animation`, and `explicit(_:)` schedules, on the host's clock: it updates once per period as `advanceTime` or the manual clock moves, not with the real time. `ViewHost.date`, `referenceDate`, and `secondsUntilNextTimelineUpdate` report the host's date (#72).

- Recorded interaction tests. `parhelion run --record FLOW.json` writes what you do in the window
  as a JSON flow: taps that name the control by accessibility identifier, else label, else node,
  drags, scrolls, typing, the pauses between them, and checkpoints of the screen at the start, at
  the end, and whenever you press F2. `parhelion test FLOW...` replays flows without a window on
  the manual clock, compares the tree at each checkpoint, prints the lines that differ, exits
  nonzero on a failure, and rewrites checkpoints with `--update`. `ViewHost.replay(_:)` runs a
  `Flow` from Swift Testing, and apps list a new `flowReplay` capability.

- Placeholder for #66 (comparison with Apple's SwiftUI on Rustle's screens): the change for that issue replaces this line.

- Faster layout and drawing on long lists and animated screens: layout keeps the sizes it chose
  for nodes between frames, text keeps its wrapped lines, and the font keeps glyph outlines and
  the coverage of each glyph, so a scrolled list or an animation frame measures and draws only
  what changed. Text also has letter spacing from Inter's dynamic metrics, which narrows it by
  about 1 to 2 percent at body size toward San Francisco's widths, so every text width and the
  README images changed. Shadows, gradients, layers, and text also draw faster over opaque
  pixels, and `RustleCollection` and `RustleNowPlaying` in `Examples` are the screens this was
  measured on. A frame in which only a scroll view's content moved copies the last frame's pixels
  shifted by the scroll and draws only the rows that came into view and whatever changed, the
  position of scrolled content is rounded to a whole pixel as on a device, and the large copies,
  gradients, shadows, and the scroll edge effect use several threads. See ADR 0019. A lazy stack
  moves the rows it placed in the last layout instead of placing them again, and the renderer no
  longer asks Foundation for the processor count, which takes about 20 µs on Linux, for each pass
  it splits among threads. The window host sends the next tick as soon as the app answers, so the
  app draws the next frame while the host shows this one: an app that takes most of a refresh
  for each frame is shown at every refresh, and a frame is on screen up to one refresh later
  after the input it shows. A few slow frames no longer slow the frames after them, and the host
  sees the app's answer as it arrives instead of about a millisecond later. See ADR 0020.

- The scroll edge effect. A `ScrollView` or `List` as the screen of a navigation stack, or the
  content of a tab view, takes the whole screen and starts its content below the navigation bar,
  so content scrolls under the bar and the tab bar. While content lies under a bar, the scroll view
  blurs it: the soft style (a heavy blur that fades out toward the content) or the hard style (a
  light blur under a nearly opaque cover with a dividing line), in light and dark, at the top
  under the navigation bar and at the bottom above the tab bar. `scrollEdgeEffectStyle(_:for:)`,
  `scrollEdgeEffectHidden(_:for:)`, and `ScrollEdgeEffectStyle`; `.automatic` is the soft style.
  A scroll view records `contentUnderBars`, `scrollEdgeEffectTop`, and `scrollEdgeEffectBottom`.
- `contentMargins(_:_:for:)`, `safeAreaPadding(_:_:)`, and `ignoresSafeArea(_:edges:)`, with
  `ContentMarginPlacement` and `SafeAreaRegions`.
- README images of a scrolled list under both bars, in the soft and hard styles, in light and dark.
- Compile-only stubs for the SwiftUI API that Rustle's iPhone app uses and Parhelion did not have:
  lazy stacks, `swipeActions`, `refreshable`, `onMove`, `onDelete`, `EditMode`, `Menu`,
  `contextMenu`, `searchable`, `ProgressView`, `ScrollViewReader`, `scrollPosition`, `glassEffect`,
  `GlassEffectContainer`, gestures, `rotationEffect`, `blur`, `mask`, `matchedGeometryEffect`,
  `sensoryFeedback`, `scenePhase`, `PasteButton`, `lineLimit`, `TimelineView`, and more. They
  compile and draw their content, and do nothing else yet.
- `MediaPlayer` and `AVFAudio` modules on Linux, as compile-only stand-ins for Apple's frameworks,
  and an empty `ParhelionTesting` target.

### Changed

- Sheets, alerts, and prominent glass match an iPhone 18 Pro Max with iOS 27.2. A medium sheet
  rests higher (451 points down a 956-point screen, not 478), floats as glass with a grabber in
  front of its content and bottom corners that follow the screen's, and its list shows the glass
  through. A `.confirmationAction` toolbar button is plain glass, not blue. Alerts are 320
  points wide, with a 15-point secondary-gray message and 47⅓-point buttons. `.glassProminent`
  is a darker, translucent tint over the blurred backdrop.

- A scroll view that reaches the top or bottom of the safe area takes the whole screen height, and
  starts its content at the safe area, so its frame and `contentOffset` count from the top of the
  screen. Scrolling stops with the last row above the bottom inset. A navigation bar draws over
  the screen it scrolls under, and its buttons receive taps first.
- `ViewHost.tapButton(labeled:)` taps any control with the label, such as a toggle's switch, and
  reports a disabled control as not tappable.

- `parhelion mcp`'s `tap` and `drag` tools describe the controls they drive.

- Screenshots from `parhelion mcp` and `--png` images show the status bar and the home indicator,
  as Simulator screenshots do.

- Rectangles render through a fast path, so a full frame takes about 7 ms in a debug build
  instead of 45 ms.
- Build errors from `parhelion run` are plain text, without the compiler's color codes.
- Symbol images take their size from the font around them as well as the image scale, and
  `imageScale(_:)` applies to every image inside the view it modifies, as in SwiftUI. A symbol
  image records its font as a `font` attribute when it is not the body style.
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
- Inset grouped lists follow the iOS 27 UI Kit: sections have a corner radius of 26, rows are
  52 points tall with 16-point side insets, separators stop 16 points short of the trailing
  edge, headers are semibold 17-point text in a 42-point block, footers are 13-point text, and
  sections are 20 points apart. The disclosure indicator is slightly larger and thinner.
- The preview window paces animation to the display: it turns on vsync, reads the display's
  refresh rate (again when the window moves to another display), and ticks the app after each
  refresh with the time the next frame will be on screen. A push in the Tasks example now shows
  a new frame every refresh, one period apart, instead of frames 9 to 23 ms apart. When nothing
  moves, neither process uses CPU.
- Frames travel from the app to the window through shared memory instead of the socket: about
  0.2 ms per frame instead of 3 ms.
- `parhelion run` and `parhelion mcp` build Parhelion with optimization in debug builds while the
  app stays unoptimized, so frames render in about 2 ms instead of 16 ms and app edits rebuild as
  fast as before. Apps that pin Parhelion to a version get the whole build optimized instead.
  Builds go to `.build/parhelion`.
- `parhelion run` notices saved files with inotify, within a millisecond instead of up to
  0.75 s, and falls back to checking twice a second where inotify is not available.
- The preview channel reads each message straight into its final array, without the 64 KB reads
  and repeated copies it made before.
- Controls follow iOS 27's Liquid Glass, approximated with the new drawing primitives: a soft
  shadow, a blur of what is behind (skipped over a flat color), a tint, and bright and dark edges.
  - Toolbar items sit on 44-point glass circles and capsules, 16 points from the screen's edges
    and 12 apart, with medium near-black labels instead of blue ones. Adjacent items share a
    capsule, and a `.confirmationAction` button is blue prominent glass.
  - The back button is a chevron on a glass circle, without the previous title. Its `label`
    attribute is that title, so `tapButton(labeled:)` and agents still find it by the title.
  - Alerts are 300 points wide, with continuous 34-point corners, a left-aligned semibold title and
    gray message, and capsule buttons: two side by side, more stacked. The screen behind dims
    blue-gray.
  - Sheets start at the top of the safe area, with continuous 38-point corners and a shadow, and
    their navigation bar leaves 16 points above its buttons. Sheets at a partial detent are
    inset glass with four rounded corners.
- List sections have continuous corners.
- The `Counter` example uses `.bordered` and `.borderedProminent` buttons, and the README shows
  the `Tasks` example's screens.
- Animation frames with Liquid Glass render fast enough for 120 Hz. At 2× in an optimized build,
  a frame of an alert fading in takes 1.6 ms instead of 7.5, of a sheet sliding up 3.4 ms
  instead of 7.3, and of a list scrolling under toolbar glass 3.1 ms instead of 4.2; at 3×,
  3.8, 7.0, and 5.2 ms instead of 15.6, 14.5, and 7.5. `ViewHost` keeps the screen beneath a
  sheet or an alert, a fading presentation at full opacity, and glass whose backdrop did not
  change from one frame to the next, and reuses them only where the result is the same, byte
  for byte. The first frame of an alert, which the preview draws when the tap arrives, draws it
  at full opacity once, in about 8 ms at 2×. Fills composite fully covered pixels of an opaque
  color as whole words and round without calling into the C library.
- The preview window's title says "Not running" when the app exits, as it already did when a
  rebuilt app failed to start.
- An app's own `@State` belongs to its `ViewHost`, as a view's does: changing it updates the tree,
  and hot reload keeps it when its value is `Codable`, including an `@Observable` model.
- `ViewHost.update()` runs lifecycle actions after it resolves the tree, and resolves the tree
  again when they change state, up to `ViewHost.maximumUpdatePasses` times. Then it writes a
  warning that names the actions and stops until the next change.
- Every `ViewHost` method that delivers input, and every agent command, first updates the tree if
  state changed, so input reaches the views on screen now.
- In a preview session, the app receives messages on a background thread, and its main thread
  runs main-actor work while it waits, such as `task` actions and `Task`s that buttons start. The
  window shows the changes that work makes without waiting for input.
- Without a window, an app waits up to five seconds for `task` work before it prints its tree or
  writes `--png`.

- The Settings example's Appearance picker sets the app's preferred color scheme.
- The web page receives an `appearance` message with the current setting, after its hello and
  status.

### Fixed

- The first click on an unfocused preview window reaches the app. Before, SDL used the click only
  to focus the window.
- `parhelion mcp --window` opens its window instead of stopping with an argument parser error.
- An app that paces its own frames, for a window host without the host clock, keeps a fixed
  60 Hz grid. Before, its timeout was truncated to whole milliseconds, so it drew every 16 ms
  and measured time from whenever it woke.
- A sheet or an alert that fades in or out fades as one layer, as on iOS. Before, each part
  faded on its own, so the blur of an alert's glass showed at full strength from the first frame
  of its fade.
- An optional environment value set to `nil` reads as `nil` instead of its default value.

[Unreleased]: https://github.com/JarrarDoga/parhelion/commits/main
