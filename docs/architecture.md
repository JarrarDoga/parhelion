# Architecture

This document describes how Parhelion turns SwiftUI source code into something you can inspect and
drive on Linux. It covers the parts that exist today and marks the planned parts as planned.

## Goals

1. **Source compatibility.** Code written against SwiftUI compiles against Parhelion without
   changes. The same package builds for iOS with Apple's SDK and for Linux with Parhelion.
2. **Behavioral fidelity.** Where Parhelion implements an API, the API behaves the way SwiftUI
   does, including identity, state lifetime, and update rules.
3. **Interactive.** A person uses the app in a live preview window with a mouse and keyboard, and
   the window reloads when the source changes.
4. **Programmable.** Everything a person can see or do in the preview is also available to code as
   data and function calls: the tree, the state, input, and (planned) time. The window is one
   client of the runtime; tests and agents are others, and they can run without a display.

Pixel-perfect rendering is not a goal. Parhelion aims to look close enough to judge a layout, and
to behave exactly enough to test against.

## Modules

| Module | Platforms | Role |
| --- | --- | --- |
| `ParhelionUI` | Linux (macOS planned) | The SwiftUI-compatible API, layout, and the runtime. |
| `ParhelionRender` | Linux (macOS planned) | Font parsing, anti-aliased rasterization, and PNG encoding, in pure Swift. |
| `ParhelionPreview` | Linux | The protocol and socket channel between an app and the window host. |
| `ParhelionTesting` | Linux | Snapshot expectations for Swift Testing: `ViewHost.expectSnapshot`. Only tests link it. |
| `parhelion` (in `Tools/parhelion-cli`) | Linux | The command-line tool, the SDL3 window host, and the web preview. A separate package, because it depends on SDL3. |
| `SwiftUI` | Linux only | Re-exports `ParhelionUI` so that `import SwiftUI` compiles. See [ADR 0001](adr/0001-swiftui-module-shim.md). |

Planned: an agent server. See the [roadmap](roadmap.md).

## The pipeline

```text
  View values          ViewHost / Evaluator          ViewNode tree
 ┌────────────┐  body   ┌──────────────────┐  data   ┌──────────────┐
 │ ContentView│ ──────► │ resolve, install │ ──────► │ Root         │ ──► tests, agents,
 │  VStack    │         │ state, register  │         │ └─ VStack    │     renderer (planned)
 │   Text ... │ ◄────── │ actions          │         │    ├─ Text   │
 └────────────┘  taps   └──────────────────┘         └──────────────┘
```

### Views

A `View` is a value with a `body`. Custom views compose other views. Primitive views (`Text`,
`VStack`, `Button`, and so on) have `Body == Never` and conform to the internal `PrimitiveView`
protocol, which turns them into nodes directly. The `ViewBuilder` result builder produces
`TupleView` for several children, `_ConditionalContent` for `if`/`else`, and `Optional` for
`if` without `else`, as SwiftUI does.

### Evaluation

`ViewHost` owns a root view. To produce the tree, its `Evaluator` walks the hierarchy:

1. If the view is primitive, it creates a `ViewNode` and evaluates any children.
2. Otherwise, it installs the view's dynamic properties (see *State*), reads `body`, and
   evaluates the result.

Each view is evaluated at a `ViewPath`, its structural position: the chain of view types and
child indices from the root. The path becomes the node's `NodeID`, for example
`ContentView/VStack/1/Text`. Modifiers do not add a path component, so applying a modifier does
not change a view's identity. Conditional branches add `if` or `else`, so the two branches of an
`if` have different identities, as in SwiftUI.

Evaluation is currently a full pass over the tree on every update. Incremental updates that
evaluate only views whose inputs changed are planned. SwiftUI uses a dependency graph (the
*attribute graph*) for this.

### State

`@State` wraps a value that the host, not the view, owns. View values are recreated on every
update, so a `State` instance cannot hold its value directly. Each `State` instead holds a small
reference, a *location*. Before reading a view's `body`, the evaluator finds the view's `State`
properties with reflection and points each location at host-owned storage keyed by the view's
path and the property name.

Two rules follow from this, and both match SwiftUI:

- State survives updates for as long as the view stays at the same structural position.
- When a view leaves the tree, the host discards its state. If the view comes back, it starts
  from its initial value.

Writing to a `State` marks the host as needing an update. `ViewHost.tap` runs the action and
then updates, so a test or an agent always observes a consistent tree.

`@Binding` is a pair of get and set closures. `$value` on a `State` produces a binding that
writes through to the host-owned storage. `$value.name` is a binding to one property, and a
binding to a mutable collection is a collection of bindings to its elements, which is how
`ForEach($items) { $item in ... }` hands each row its element. A binding to an `Identifiable`
element, or one from `ForEach` with an `id` key path, finds its element by identifier on every
read and write, so a row's binding stays with its element when earlier elements are inserted or
removed; other element bindings follow their position. Once its element is gone, a binding
returns the last value it read or wrote, and writes to it do nothing.

An app's own `@State` belongs to the host too. The root of the tree is the app, which installs
its dynamic properties under the app's type name, such as `LibraryApp._library`, and evaluates
the first window's content in its place.

### Observation

`@Observable` models use the Swift toolchain's Observation module; `import SwiftUI` re-exports it,
and Foundation, as Apple's SwiftUI makes both available.
Each evaluation of the tree runs inside `withObservationTracking`, which records every
observable property that a `body`, a binding, or presented content reads. The first change to any
of them marks the host as needing an update, the same way a `State` write does, so `@State`
holding a model, `@Bindable`, and models in the environment all invalidate the same way.

- Observation calls back before the change, on the thread that makes it. On the main actor the
  host is marked at once, so a change inside `withAnimation` animates. From another thread the
  mark waits for the main queue.
- Tracking ends with the first change, and each evaluation tracks again. Observation starts
  watching only after an evaluation returns, so the previous evaluation's tracking stays active
  until then, and a change that another thread makes during an evaluation, to a property the
  previous one read too, is not lost. A property that an evaluation reads for the first time and
  another thread changes before the evaluation returns is missed until the next update.
- After an evaluation is tracked, the host changes a private observable value that the previous
  evaluation read, which ends the previous tracking even when only `@State` changed, so
  trackings never pile up in a model.
- A view does not track its own reads, and the host does not re-evaluate only the views whose
  properties changed: evaluation is still a full pass.

### The view tree

`ViewNode` is plain data: a kind, an identifier, string attributes, and children. It is
`Codable`, `Sendable`, and `Hashable`, so it can be serialized, compared across updates, and
sent to another process. Modifiers record themselves as attributes on the nodes they affect,
for example `padding=all`.

The tree is the contract between the runtime and everything that consumes it. Tests assert on
it, agents read it, and the planned renderer will draw it. A renderer will consume the tree
after layout adds frames, and it will never read view values directly.

### Layout

After evaluation, `LayoutEngine` assigns a frame to every node, in screen points. It follows
SwiftUI's model: a parent proposes a size, the child chooses its own size, and the parent places
the child. A `nil` dimension in a proposal asks for the child's ideal size.

- **Stacks** use SwiftUI's algorithm. The stack subtracts its spacing from the proposal and offers
  the remaining length to its children one at a time, least flexible first. Each child gets an
  equal share of what is left, and space a child does not use passes to the children after it.
- **Layout modifiers** (`padding`, `frame`) are stored on each node in order, innermost first,
  because the order changes the result. A node's `frame` is its own bounds, without its outer
  padding or frames, which is also the area that receives taps.
- **Text** is measured with the advance widths of the bundled Inter typeface and wraps at spaces.
  The four weights in `Fonts/` (Regular, Medium, SemiBold, and Bold) are generated into source,
  because Parhelion cannot ship SwiftPM resources ([ADR 0003](adr/0003-no-swiftpm-resources.md)).
  There is no kerning or shaping. Every character is followed by a letter spacing that depends on
  the size, from Inter's dynamic metrics, which brings Inter's widths toward San Francisco's
  ([ADR 0019](adr/0019-layout-and-glyph-caches-and-letter-spacing.md)).
  Layout keeps the sizes it chose and the lines text wrapped into between frames, and a font keeps
  its glyph outlines and each glyph's coverage by size and quarter pixel, so a scrolled list or an
  animation frame measures and draws only what changed. A cached size is used only for a node
  equal to the one it was measured for, and a size that read a lazy stack's measured lengths is
  not kept.
- **Fonts** flow down through the environment: `font(_:)`, `fontWeight(_:)`, and `bold(_:)` set
  them for their content, and `Text.font(_:)` overrides them. Each `Text` resolves its font when
  it is evaluated and records it as an attribute, such as `font=headline` or
  `font=largeTitle.bold`, unless it is the body style. Layout and drawing read only that
  attribute: a text style's size, line height, and weight come from `LayoutDefaults`, and the
  weight picks the nearest bundled Inter.
- **Line limits and truncation** (`TextLimits.swift`) are environment values, as in SwiftUI:
  `lineLimit(_:)` and `truncationMode(_:)` reach every `Text` and `TextField` inside the view.
  A `Text` records `lineLimit`, `reservesSpace`, and `truncationMode` (only when set). Layout
  and drawing wrap the text, and when it needs more lines than the limit, the last line (tail),
  the first (head), or the middle one stands for the lines that do not show and is cut to the
  width with an ellipsis, `…`, at a character boundary. Layout and drawing call the same
  function, so they agree. A range's upper bound is the limit, and its lower bound is the fewest
  lines the `Text` takes, as in SwiftUI.
- **Dynamic Type** scales text styles: each `Text` resolves its font at the environment's
  `dynamicTypeSize`, with the size and line height of the iOS 27 UI Kit's Dynamic Type table
  (`DynamicTypeTable`), and records the size in `fontSize` when it differs from the size at
  Large, as in `font=title fontSize=34`. Within a style, every size has one line height, so
  layout and drawing find the line height from the style and the size. A custom font scales by
  the ratio of its text style's sizes, as `@ScaledMetric` does; the system font at a fixed size
  does not scale. List rows, footers, text fields, large titles and their bar, and bordered and
  alert buttons grow with their text. Toolbar items are evaluated at Large, and the tab bar and segmented
  controls use fixed sizes, so they keep their size, as on iOS. Each line is the line height tall, with the difference
  from Inter's own height split above and below the glyphs, and the renderer draws with the same
  font and baselines so that layout and pixels agree.
- **The root** covers the device screen. Root content is proposed the safe area and centered in
  it. `Device.iPhone16` is the default; `PARHELION_DEVICE` picks another preset from
  `Device.all`.
- **Shapes and images.** A shape, a `Color`, a `LinearGradient`, and a resizable image fill the
  space they are offered, 10 points without a proposal. An image that is not resizable is its
  size in points, which its node records as `size`, and a missing image is a symbol's square.
  `aspectRatio(_:contentMode:)` proposes its view the largest size with its ratio inside the
  proposal, or with `.fill` the smallest that covers it.
- **Overlays.** `overlay(alignment:content:)` adds an `overlay` layout modifier and appends an
  `Overlay` node with its views as the last child of each node it covers. Layout sizes and places
  the node without its `Overlay` children, then places the views of the first `overlay` modifier's
  `Overlay` child, the second's, and so on, in the bounds at that modifier's place in the chain,
  as a `ZStack` with its alignment does. Hit testing reaches them first, as the last children, and
  `ViewNode.label` leaves them out.
- **Grids.** A `LazyVGrid` lays out its columns across the width it is offered: fixed items and
  spacing first, then flexible and adaptive items share the rest equally within their bounds,
  and an adaptive item holds as many columns of its minimum as fit. Cells fill rows leading to
  trailing, each row as tall as its tallest cell; a `LazyHGrid` is the transpose. Parhelion
  evaluates every cell, not lazily. A `Grid`'s columns are as wide as the widest of their cells
  that span only them, and its rows as tall as their tallest cell; with more space, columns and
  rows with flexible cells share it, and a view outside a `GridRow` spans every column. The
  default spacing of all three is 8 points.

Every number in which Parhelion assumes SwiftUI's behavior, such as the default padding of 16
points, is in `LayoutDefaults.swift`. These are assumptions until the planned macOS fidelity job
verifies them.

### Rendering

`ViewHost.render(scale:chrome:)` draws the laid-out tree into a `RenderedFrame`, an RGBA image at
the given number of pixels per point. Like layout, the renderer reads only the tree, and the
device for the system interface it draws over the tree.

- **Drawing** happens in `ParhelionRender`, a module with no dependencies. It parses Inter's
  TrueType outlines, flattens curves, and fills paths with exact-area anti-aliasing. There is no
  GPU and no system font library, so the same tree produces the same pixels on every machine
  ([ADR 0004](adr/0004-pure-swift-renderer.md)). For Liquid Glass, the canvas also draws
  continuous ("squircle") corners, rings, linear gradients, blend modes, blurred drop shadows,
  and a blur with saturation of the pixels already drawn. Shadows and blurs approximate a
  Gaussian with three box blurs on integers, at a reduced resolution for wide blurs, so their
  cost follows the area they cover: at 3× in an optimized build, a 44-point control's shadow
  or blur takes about 0.5 ms, and an alert's blur about 3 ms. Shapes and their rings rasterize
  only their corners.
- **Glass** is drawn by `Canvas.drawGlass` in ParhelionUI, with the materials in `ColorPalette`:
  a drop shadow, a blur of what is already drawn behind, a tint, a bright line inside the edge,
  and a faint ring outside it. Small glass is for toolbar items, the back button, and `.glass`
  buttons; large glass for alerts and partial-height sheets. Prominent glass mixes its tint
  color toward black (light) or white (dark) and draws it translucent over the blurred backdrop,
  as an iPhone with iOS 27.2 does. Before blurring, it checks whether
  the pixels the blur would read are one flat color, every row at one pixel per point, and then
  skips the blur and fills the shape with the tint blended over that color once.
- **`glassEffect`** plugs in through the extension seam (Rendering+GlassEffect.swift). The modifier
  draws its glass behind its view in the shape, with the small glass of toolbar buttons, the large
  glass of alerts for a shape 140 points across or more, a trace of frosting for `.clear`, and the
  prominent glass for a tint. A shape on its own goes through `Canvas.drawGlass` and the cache like
  a bar. A `GlassEffectContainer` is laid out as a `ZStack`, marks the glass inside it as its own,
  and draws it before its children: shapes of the same glass closer than its spacing (or touching)
  draw as one piece, with a neck between them that thins as they part. A merged piece draws the
  shadow of the union, the glass inside the union (a clip), and each shape's edge cut away where
  another shape covers it; the cache keeps it like any glass (`EntryKey.merged`). A shape with a
  `glassEffectID` that fades in or out draws between the frame of the nearest settled glass in its
  namespace and its own, so the presented tree's opacity drives the morph.
- **Colors** come from `ColorPalette`, which maps SwiftUI's named colors and styles to iOS 27's
  system colors in the light or the dark appearance. The renderer reads the color scheme from
  the tree: the root records `colorScheme=dark` while the window is dark, and a node records its
  own where its content's scheme differs, from `environment(\.colorScheme, _:)` or a
  presentation's preference. Every color and material the renderer draws comes from the
  scheme's `ColorPalette.Appearance`; content in a sheet uses the elevated dark backgrounds.
  Colors that the kit blends with glass, plus-lighter in dark, are drawn as the color they make
  over the dark glass, as light draws its plus-darker colors over light glass. A `foregroundStyle` applies to the node and its descendants, and
  so does a `tint`. Button labels take the tint color unless they set their own style or their
  button style chooses another, and labels on glass are near-black.
- **Buttons** read a style, a control size, and where they are from the environment while they
  are evaluated, as `buttonStyle(_:)` and `controlSize(_:)` set them for all the buttons inside.
  A button records its style and size as attributes; layout makes a bordered or glass button a
  capsule around its label, and the renderer draws the capsule. A custom `ButtonStyle`'s body is
  evaluated in place of the label.
- **Backgrounds** fill the bounds at their position in the modifier chain. Each node records those
  bounds in `modifierFrames`.
- **Styles** are strings in the tree, a `ShapeStyle`'s `styleName`. A color is its name, and a
  linear gradient is `linearGradient(red 0, blue 1, top, bottom)`: each stop's color and location,
  then the start and end unit points. The renderer reads a style back as a color or a gradient
  (`StyleDescription`) and resolves each color with the node's tint, opacity, and color scheme,
  so a gradient can fill any shape, background, symbol, or overlay.
- **Shapes** draw from their node: the kind names a built-in shape, with its `cornerRadius` and
  `style`, a `Path` records its SVG path data, and a shape of an app's own type records its
  description, `String(describing:)` of the shape, as `shape`. The renderer asks such a shape for
  its path in its frame through `CustomShapes`, a table of the shapes evaluated, by description,
  shared in the process. Rectangles, rounded rectangles, capsules, and circles skip the general
  rasterizer when filled with a color.
- **Effects.** `clipShape`, `cornerRadius`, `shadow`, `scaleEffect`, and `overlay(_:in:fillStyle:)`
  are layout modifiers that do not change layout, so each applies at its place in the chain.
  Drawing a node with any of them goes from the outermost modifier in: backgrounds outside the
  outermost effect draw behind and overlays in front, the effect applies to everything inside it,
  and that draws the same way down to the node itself. A clip keeps the pixels inside the shape's
  bounds, draws, and puts back those outside the shape (`Canvas.beginClip` and `endClip`), so its
  cost follows the shape's size. A shadow draws its inside on a transparent layer with the
  node's frames moved to the layer's origin, blurs the layer's opacity under it with a standard
  deviation of the shadow's radius, and blends the layer over. A scale draws its inside on a layer
  at the scale it shows at, lined up with the canvas's pixels when both axes scale alike, so text
  stays sharp; taps still reach the unscaled frame.
- **Rotation, blur, and mask** (`Effects+Transform.swift`, `Rendering+Transform.swift`) are custom
  layout modifiers that the renderer draws through one hook in `drawChain`, because each draws the view inside
  it on a layer of its own. The layer is lined up with the canvas's pixels. A rotation blends the layer over
  the canvas turned clockwise around the anchor in the bounds at its place in the chain, sampling bilinearly
  (`Canvas.draw(layer:atPixelX:y:rotatedBy:aroundX:y:)`); taps still reach the unrotated frame. A blur takes
  the radius as the Gaussian's standard deviation, reaches three of them past what the view draws, and
  blurs the layer with `Canvas.blur`; `opaque` blurs only the bounds and repeats the edge pixels. A mask is
  evaluated as an `overlay` is, as an `Overlay` child placed by the `overlay` modifier that comes just before
  the `mask` modifier; the renderer draws those views on a second layer and multiplies the first layer's opacity
  by theirs (`Canvas.multiplyOpacity(by:)`). The layers draw without the render cache.
- **Images** from asset catalogs are read from disk at run time, because on Linux SwiftPM copies
  an app target's `Assets.xcassets` unprocessed into the target's `<Package>_<Target>.bundle`
  ([ADR 0010](adr/0010-images-from-the-app-bundle.md)). An image's node records its `name`, its
  `bundle` when one was given, its `size` in points from its largest file's PNG header, and
  `appearance=dark` when the environment is dark and the set has a dark file. The renderer
  finds the file for its scale, the smallest at least as large, and `ImageLibrary` decodes it
  with `ParhelionRender`'s PNG decoder and keeps it, with halved levels for drawing it small, up
  to 256 MB. Bitmaps are drawn with bilinear sampling, in nine parts for cap insets, and in the
  foreground color for a template. A missing image, or a JPEG, PDF, or HEIF file, records
  `missingImage=true` and draws as a ring.
- **Symbols** are drawn with [Phosphor Icons](https://phosphoricons.com), because Apple's license
  does not allow shipping SF Symbols outside Apple platforms
  ([ADR 0007](adr/0007-phosphor-symbol-images.md)). `Symbols/symbols.txt` maps common SF Symbol
  names to Phosphor icons, and `Scripts/embed-symbols.sh` generates their SVG path data, regular
  and fill weights, into source. A name with a `.fill` suffix draws the fill weight. Every lookup
  goes through `SymbolLibrary.resolve`, which returns an outline in a unit square and the source
  that drew it: the back button's chevrons are Parhelion's own, the user's own SF Symbols come
  next when they have imported them ([ADR 0021](adr/0021-user-sf-symbols.md)), then Phosphor, and a
  name no source has is a ring, whose node records `missingSymbol=true`. A name drawn from the
  user's symbols records `symbolSource=sfSymbols`. A symbol is a square as wide as its font's size,
  scaled by its image scale, and Phosphor's 256-unit grid spans 4/3 of that side.
- **Rectangles**, most of what an interface draws, skip the general rasterizer: each pixel's
  coverage is its exact overlap with the rectangle, and fully covered runs are written as whole
  32-bit words. A typical screen renders in under 1 ms in an optimized build.
- **PNG** output uses a small built-in deflate encoder. A screen of mostly flat color compresses
  to about 50 KB at 2× scale. PNG input goes through a pure-Swift inflate, with stored, fixed,
  and dynamic Huffman blocks, and reads every color type and bit depth, transparency, the five
  row filters, and Adam7 interlacing.
- **Device chrome** draws over everything the app presents. `.systemBars` adds the status bar
  and the home indicator, which is what a Simulator screenshot shows; agent screenshots and
  `--png` use it, so every point of the image is a point on the screen. `.screen` also adds the
  Dynamic Island or notch and blacks out the screen's rounded corners; the preview session sends
  these frames. Each `Device` preset records its corner radius, cutout, and home indicator width.
  The bars follow the window's color scheme: black in light and white in dark. The status
  bar's clock uses Inter SemiBold in place of SF Pro. The chrome depends only on the device, the
  scale, the kind of chrome, and the scheme, so `ViewHost` draws it once into a `CanvasOverlay` and blends
  that over each frame: opaque runs are copied as whole words, and only the anti-aliased edges
  are blended.
- **Frames that animate** reuse drawing from earlier frames, kept by `ViewHost` in a
  `RenderCache`. Whatever it reuses is the same, byte for byte, as drawing it again, and tests
  check every kind against frames drawn from scratch. The screen beneath the frontmost sheet or
  alert is kept while that part of the tree, and the pressed or focused view in it, stay the
  same, so a frame of a presentation moving draws only the presentation. A presentation that
  fades draws as one group, the way Core Animation fades a layer: at full opacity, then blended
  over the screen beneath with its opacity, so the blur of its glass fades in with the rest.
  The cache keeps the full-opacity layer, and each frame of the fade is one blend. A glass
  surface drawn with the same arguments in two frames in a row is kept with the pixels of its
  region (`Canvas.glassRegion`) before and after it was drawn; a later frame that finds the same
  pixels there copies the result instead, as for toolbar buttons over the bar while a list
  scrolls. The cache holds at most two full-screen canvases, the backdrop, which goes when
  nothing is presented, and the layer, which goes when nothing fades, and up to 16 MB of glass,
  which goes when a frame does not draw it. At 2× in an optimized build, a frame of an alert
  fading in takes about 1.6 ms, of a sheet sliding up 3.4 ms, and of a list scrolling under
  toolbar glass 3.1 ms.
- **The bezel** exists only in the window and the web page. The window host draws the phone
  once, with a transparent hole the shape of the screen, and draws it over each frame. The window ends at the
  phone's side buttons and is transparent outside the phone where the compositor supports it, so
  the host also fades out the frame's square corners where they reach past the phone's rounded
  body. Pointer positions are moved by the bezel's margin before they go to the app.

### Scrolling and time

A `ScrollView` takes the space it is offered and lays its content out at its ideal size along
the scrollable axes. Several content views stack along the scroll axis, as in SwiftUI. `ViewHost`
keeps each scroll view's offset by node identifier, so scrolling lays the tree out again without
evaluating views, and the renderer clips the content to the scroll view's bounds.

- `scroll(by:at:)` scrolls the innermost scroll view under a point that can move that way, as a
  mouse wheel does.
- A press over a scroll view that moves more than 10 points becomes a drag: the button press is
  cancelled and the content follows the pointer, as on iOS.
- A release while moving keeps the content moving. The speed decays at iOS's normal deceleration
  rate until it stops or reaches the end of the content.

Momentum runs on the host's own clock, which advances only through `advanceTime(by:)`, in fixed
steps. The same input at the same times always produces the same frames, however the time is
split, so tests and agents can step animations exactly. The preview session advances the clock
to the moment each frame will be on screen and draws once per display refresh while anything
moves (see *The preview window*). On a manual clock, `advanceTime` moves it instead, together
with every `Task.sleep`. `ViewHost.revision` increases whenever the screen changes, and
the session sends a frame only then.

### Scroll targets, positions, and geometry

A view's identifier names a scroll target. `id(_:)` records it as `viewID=Type:value` and, as in
SwiftUI, makes it part of the view's identity; a `ForEach` element's identifier names its views
unless they have an `id(_:)`. The evaluator keeps the identifiers by node (`ScrollEvaluation`) and
the host adopts them with each evaluation (`ScrollHostState`), so the tree stays plain data.

- **Requests.** `ScrollViewProxy.scrollTo` and a changed `scrollPosition` binding queue a
  `ScrollRequest` and mark the host for an update. After the update's layout, `relayout()` applies
  the requests: it finds the first node with the identifier, takes the innermost scroll view above
  it, sets that scroll view's offset so the node's frame sits at the anchor in the visible region
  (the scroll view's bounds less its insets), and lays out again. A request therefore sees the
  views its own action changed, and `withAnimation` animates it as a layout change.
  Without an anchor, `scrollTo` scrolls by the least that shows the view, and a bound position
  puts the view at the start. A list row scrolls by its cell.
- **Lazy rows.** A row of a lazy stack or list that does not exist yet is found by its `ForEach`
  identifier among the stack's slots. The request scrolls to where the slot would be, from the
  measured lengths and the mean for the rest; that makes the host create the rows there, and the
  request runs again, up to three times, until the row exists and sits at the anchor. A row known
  only by an `id(_:)` inside it cannot be found before it exists.
- **Bindings.** After each layout, a scroll view with a bound position that moved since the host
  last honored or wrote the binding writes the identifier of its first target whose end is past
  the start of the visible region. The host remembers the value it wrote, so a binding it wrote is
  not scrolled to again. The first offset the host sees is the starting point: the binding stays as
  the app set it until the user scrolls. `ScrollPosition` also receives the offset as `point`.
- **Targets.** The children of views marked with `scrollTargetLayout()` are the targets, or, with
  none marked, the outermost views with an identifier.
- **Settling.** `scrollTargetBehavior` flows down the environment and is recorded on scroll views
  as `scrollTargetBehavior=paging` or `viewAligned`. When a drag ends, `ViewHost.pointerUp` asks
  `settleScroll` first and starts momentum only if the scroll view has no behavior. Paging
  moves at most one page from where the drag began: past half a page, or faster than 300 points
  per second. View alignment moves to the start of the target nearest where the content would
  coast, at most one target away on a horizontal scroll view, as `limitBehavior` says. The wheel,
  `scroll(by:at:)`, and `scroll(_:to:)` do not settle.
- **Geometry.** `onScrollGeometryChange` runs after each layout with the scroll view's
  `ScrollGeometry` and calls its action when the transformed value changes, and once at first.
  The content offset is relative to the content's origin, so it is negative while the content sits
  below an inset, as on iOS.

### Scrolling under bars

A scroll view that scrolls vertically and reaches the top or bottom of the safe area takes the
whole screen height there. Its content starts at the safe area, or below the navigation bar when
the scroll view is a navigation stack's screen, or ends above the tab bar when it is a tab
view's content. The layout engine passes those two edges down as `ScrollLayout.obscuredTop` and
`obscuredBottom`, and a scroll view records them in its `ScrollMetrics` as `topInset` and
`bottomInset`, which `maxOffset` counts. A sheet's bar keeps its content below it. The
`contentMargins` and `safeAreaPadding` of a scroll view are padding around its content, which
scrolls with the content; `ignoresSafeArea` moves the edges of a view's space to the screen's
where they meet the safe area's.

A scroll view records `contentUnderBars` (`top`, `bottom`, or `top,bottom`) while its content lies
under a bar, so tools can see whether the scroll edge effect shows. The renderer draws a
navigation bar after its stack's screen, and draws the effect in between
(`Rendering+ScrollEdge.swift`): the **soft** style blurs the region with a radius of 100 and mixes
the blur back with a weight that falls from 0.6 at the screen's edge to 0, and the **hard** style
blurs with a radius of 6 under a tint (white at 85% in light, black at 55% in dark) with a
hairline along the inner edge. The top effect runs from the top of the screen to 6 points below
the bar's row of buttons, or to the bottom of a large title's bar; the bottom effect from 16
points above the tab bar to the bottom of the screen. Hit testing reaches a navigation bar before
the screen it covers. The effect blurs only the pixels inside its rectangle, on blocks of them
resampled bilinearly, so its cost follows the rectangle (about 2 to 6 ms at 2× and 3×). `RenderCache`
keeps an effect that stays where it was with the pixels it read and left, as it does glass, and
copies it while the pixels beneath do not change; a checksum of those pixels tells whether they
changed, so a list scrolling under the bar does not pay for copies. While a scroll moves the
content under the effect, nothing is kept: the pixels differ in every frame, and a frame skips the
checksum.

A scroll view's content is drawn from the last frame when only its position changed
(`Rendering+ScrollShift.swift`, ADR 0019). `RenderCache` keeps the pixels the content drew; the next
frame copies them shifted by the scroll and draws again the rows that came into view and the nodes
whose description changed. This needs the content's position on whole pixels, which the renderer
rounds it to, a flat color beneath the content, and content that does not read the pixels around
what it draws (`Canvas.readsSurroundings`); otherwise the content is drawn in full.

### Progress views

`ProgressView` is a primitive whose node, `ProgressView`, records its `style` (`circular` or
`linear`) and, for a known amount, `value` and `total`. Its children are the label views and one
`ProgressIndicator` node with a `shape` (`spinner`, `ring`, or `bar`) and the `fraction` completed.
The kind registers itself through the extension seam ([ADR 0011](adr/0011-extension-seam.md)): the
`ProgressView` is laid out as a vertical stack, leading-aligned with the label above the bar for a
bar and centered with the label below for a spinner or a ring, and the indicator draws itself at
20 points across (4 points thick and as wide as it is offered, for a bar).

A spinner and an indeterminate bar animate on the host's clock as an `.animation` timeline does:
the evaluation asks the host for the time (`resolveTimeline`), records the turn as `phase` (0 to
under 1), and `isAnimating` stays true while one is on screen. The spinner steps its leading spoke
once every eighth of a second; the bar's highlight crosses in 1.5 seconds. A custom
`ProgressViewStyle` gets the fraction and the labels in its configuration and builds its own body.
Assumed, not measured against a device: the sizes, the secondary color of labels, and the
indeterminate bar's look.

### Timelines

`TimelineView` reads the host's clock, not the real one, so it follows `advanceTime(by:)` and the
manual clock ([ADR 0012](adr/0012-manual-clock.md)). `ViewHost.date` is `referenceDate` plus
`time`. The reference date is the real date at the first moment a view asks for it, so a
`Date.now` read just before agrees with it, and then it stays; set it, or pass it to `ViewHost`,
to make dates repeat. (Assumed, against research for #31, which suggested a fixed date: `Date.now`
is real, so `.periodic(from: .now, by: 1)` would never fire against a fixed date.)

- The view is a primitive. Its node is `TimelineView` with `schedule` and `date`, and the
  content built for that date as its children; it is sized like an `AsyncImage`.
- The host keeps, for each timeline node, the date shown and the schedule's next date
  (`TimelineHostState`). An evaluation walks the schedule's `entries(from:)` from the date shown
  to the latest entry that has passed, so an update visits only the dates since the last one.
  The view shows that date, or the date it appeared at before the first entry.
- `advanceTime(by:)` evaluates again when a next date has been reached, once however far it
  moved, with the latest date. `advanceClock(by:)`, which the manual clock and MCP `wait` use,
  stops at each date, so a view that counts its updates sees every period.
- `.animation` is driven by frames: the view updates on every `advanceTime`, at most once per
  `minimumInterval`, with the host's date, and `isAnimating` is true while one is on screen and
  not paused, so a window host keeps asking for frames. `secondsUntilNextTimelineUpdate` covers
  schedules of dates only.
- A session that is not on a manual clock waits for the next date as it waits for the next
  animation frame (`PreviewSession.waitTimeout`), moves the clock to the real time, and sends a
  frame.
- The cadence in the context is derived: the interval of `periodic`, a minute for
  `everyMinute`, `live` for `animation`, and the gap to the next date otherwise. Less than a
  second is `live`, less than a minute `seconds`.
- `lowFrequency` mode is ignored. An `.explicit` schedule shows the latest date that has passed.

### Lists

A `List` lays out like a vertical scroll view whose content is its sections, so scrolling,
momentum, and `scroll(_:to:)` work the same way. Evaluation shapes the tree:

- Rows outside a `Section` are grouped into sections of their own, one for each run of
  consecutive rows, so a list's children are always `Section` nodes.
- A section's header and footer become `SectionHeader` and `SectionFooter` nodes around its rows.
  Inside a list, they are evaluated with the list's fonts in the environment, semibold 17 points
  for headers and 13 points for footers, so a font set inside them still wins.
- Each row gets a `listRow` layout modifier, its outermost. The row fills the width it is
  offered, is at least 52 points tall, and places its content at the leading edge inside the
  row insets, 15 points above and below and 16 at the sides. The bounds recorded for the
  modifier are the row's cell.

The renderer draws each section's cells as one rounded group, with a corner radius of 26 in the
inset grouped style, and a separator between rows, inset 16 points from both sides. Hit
testing uses a row's cell instead of its frame, so a button row responds to taps across its whole
width, and a pressed button row highlights its cell. `listStyle(_:)` records a `listStyle`
attribute that layout and drawing read.

A list shows a **section index** when `listSectionIndexVisibility` is not `.hidden` and a section has a
`sectionIndexLabel`, which a section records as the `sectionIndexLabel` attribute (`SectionIndex.swift`).
`List` adds the index as an `overlay` aligned trailing: a 28-point column of plain buttons, one for
each distinct label, 16 points apart, with a drag gesture on the column. A button, `tap(at:)`, or a
drag that reaches a letter sets the list's scroll offset to the section's distance from the first
section, so the section sits at the top of the content below a navigation bar, or as far as the
content allows for the last sections. Assumed: the sizes, and that `.automatic` shows the index.

### Lazy stacks and list rows

`LazyVStack`, `LazyHStack`, and a `List` with more than 40 rows create only the rows near the
screen ([ADR 0016](adr/0016-lazy-windows.md)). Evaluation is still a full pass, so the rows' limit
comes from a loop between evaluating and laying out:

1. The container flattens its content into *slots* without evaluating them. A `ForEach` is one
   segment with a count and an identity for each element; `TupleView`, `if`, `Group`, and `Section`
   are looked through, and any other view is one slot. A `ForEach` of `Section`s makes the slots of
   each section.
2. Evaluation creates the slots in a *window*: the first 40 at first, and later the slots that
   layout found on screen, with a margin of half a scroll view on each side. It keeps the window
   while it covers what is on screen, so scrolling evaluates once every few rows.
3. Layout measures the slots that exist and keeps each slot's length by identity. A slot that does
   not exist is as long as the mean of the others, so the content is the length of all the slots.
   Placing the container finds the slots that overlap the scroll view, its *demand*. A stack takes
   the width it is offered, which is assumed from how SwiftUI's lazy stacks behave in a scroll view.
4. After each layout, the host compares every container's demand with its window. If the window
   does not cover it, the host evaluates again and lays out again, until it does. Scroll requests
   past the end wait for this, so they land on the end of the rows that were then measured.

A view keeps its node identifiers and its `@State` keys from the structural path as in eager
evaluation. The host keeps the state of a released row for as long as the row's identity is in the
data. `onAppear`, `onDisappear`, and `task` follow the rows that exist, so the last row's
`onAppear` can load more.

The tree shows only the rows that exist. A container that holds some of its rows records
`lazyCount` and `lazyResolved`, such as `lazyCount=5000 lazyResolved=1996..<2012`. In a list, the
`Section` node holds them, and drawing reads the rows that exist, so the rounded groups and the
separators are as before. `pinnedViews` keeps a section's header or footer at the edge of the scroll
view, in front of its rows, until its section ends. A lazy stack outside a scroll view uses the
screen as its viewport. `scroll_to` sets an offset, so it reaches a row that does not exist yet:
the next update creates it. `ScrollViewProxy.scrollTo` and `scrollPosition(id:)` reach such a row
by its identifier (see "Scroll targets, positions, and geometry").

### Swipe actions

`swipeActions(edge:allowsFullSwipe:content:)` on a list row appends an `Overlay` child to the row,
as `overlay(alignment:content:)` does, so layout leaves it out of the row's own layout. In it, a
`SwipeActions` node (registered through the extension seam) holds the row's action buttons for
one edge, evaluated like any buttons, so each has an identifier, an action, and a frame. The row
records `swipeActions=trailing,leading`. Outside a list the modifier does nothing.

- **Layout.** `SwipeLayout.apply` runs after the layout engine, in `ViewHost.relayout`, on a tree
  with every row at rest. For each row it reads the offset `ViewHost` keeps (`swipe.offsets`,
  negative for the trailing actions), moves the row's content by it inside its cell, and puts
  the buttons rigidly beside it, 8 points from its edge. The cell, `listRowFrame`, stays where it
  is, and the row records `swipeOffset` while it is not at rest. A button is at least 74 points
  wide, with 16 points of padding around its label, and the first action sits at the cell's edge
  on either side. Past a threshold, the first action grows to fill the space the row left and the
  others move out of the way. Buttons of a row at rest have no area, so a tap cannot reach them;
  `tap(_:)` and `tapButton(labeled:)` still do, as they do for any node. Assumed, not measured on
  iOS 26: these sizes.
- **Input.** In `pointerMoved`, a press that moves mostly sideways on a row with actions on that
  side, or on the open row, becomes a swipe instead of a scroll, and the row follows the pointer.
  `ViewHost.drag(from:to:duration:)` goes through the same path. A row without a full swipe
  resists past its actions. On release, a row dragged more than half of its actions' width, or
  flung at 400 points per second, springs open; otherwise it closes. A row dragged to its full
  swipe distance, the larger of its actions' width plus 40 points and half of its cell, runs its
  first action. Running an action closes the row. A press anywhere but on an open row's actions,
  including a tap on the row itself, only closes it, and opening one row closes another.
- **Drawing.** Each button is a continuous rounded rectangle in its `tint`, red for a destructive
  button and gray otherwise, with white labels. A `swipeClip` modifier on the row clips what is
  inside it to the cell, so the row slides out of its cell and the buttons slide in.
  Labels are laid out as in any button: a `Label` is one line, not an icon above its title.

### Navigation

A `NavigationStack` keeps the entries above its root view in `ViewHost`, by the stack's
identifier, the way scroll offsets are kept. A link with a destination view pushes its own
identifier; a link with a value pushes the value, into the stack's path binding if it has one.
On every update the stack evaluates each screen in order, at its own path (`Destination[1]`,
`Destination[2]`, ...):

- Each screen declares the destinations of the links and `navigationDestination` modifiers it
  contains, so the next entry can be resolved. If an entry no longer resolves, because its link
  left the tree, the stack drops it and the entries above it.
- Only the top screen is in the tree, but every screen is evaluated, so the views beneath keep
  their state. A popped screen is no longer evaluated, so its state is discarded.
- Modifiers report a screen's title, title display mode, toolbar items, and back-button
  visibility to the stack through the evaluator, which holds the innermost stack being evaluated.
- The root screen's `.automatic` title is large, and each pushed screen's `.automatic` title takes
  the display mode of the screen beneath it, as in SwiftUI.

The tree is `NavigationStack` with a `NavigationBar` child followed by the top screen. The bar
records its `titleDisplayMode` and contains the back button, `ToolbarItemGroup` nodes with a
`placement` attribute, and the title as a `Text` node with its font. The back button is an
ordinary `Button` whose identifier ends in `/bar/back`, so every tap method drives it. It shows
only a chevron, and its `label` attribute is the previous screen's title, or "Back", which
`ViewNode.label` and `tapButton(labeled:)` use.

Each group of leading or trailing items is one glass capsule, 44 points tall: an item that is
only a symbol is a 44-point circle on its own and 52 points wide among others, and other items
are padded by 12 points at each end. Buttons fill their part of the capsule. A
`.confirmationAction` keeps the plain glass of the other items, as on an iPhone with iOS 27.2;
buttons with the `glassProminent` style get a capsule of their own nearer the edge, marked
`glass=prominent`. Items are evaluated with medium
labels, and the renderer draws them near-black on glass.

The stack fills the space it is offered: the bar takes the top 54 points with an inline title,
or 105 with a large one, and the screen is centered in the rest, as root content is. Inside the
bar, the back button and the groups start 16 points from each edge, 12 points apart, and they
and an inline title center in the top 44-point row. A large title starts 54 points down, at the
leading margin, so the buttons stay above it. In a sheet the bar records `presentation=sheet`
and is 16 points taller, with the row 16 points below the sheet's top. A bar with principal
items or without a title always uses the inline layout.

### Tab views

A `TabView` evaluates every tab on every update, each at its own path, so a tab keeps its state
and its navigation stacks while another tab is selected. Only the selected tab's nodes are in the
tree, followed by a `TabBar` node with one `Button` per tab: the tab's symbol, in the fill
variant, above its title. The selected tab's button records `selected=true`, and a search tab's
records `role=search` and its title as `label`. Tapping a button sets the selection binding to
the tab's value, or, without a binding, the tab view's own selection, which it keeps as host state
at its path. Tabs come from `Tab` values through `TabContentBuilder`, or, for views with
`tabItem(_:)`, from each view the content resolves to, labeled by the first symbol and text in its
tab item and selected by its `tag`, or a `ForEach` element's identifier.

Layout floats the bar over the content, 21 points above the bottom of the screen when the tab view
reaches the bottom of the safe area, as the iOS 27 UI Kit does. Tabs share the capsule's width
equally, and a search tab is a circle at the trailing end. A list or scroll view, alone or as a
navigation stack's screen, fills the tab view and scrolls under the bar: the layout engine records
the bar's top while it places the tab, and a scroll view that reaches below it gets that much
extra room at the end of its content, so its last row can scroll above the bar. Other content is
centered above the bar. The renderer draws the bar with the small glass of toolbar buttons and a
gray highlight behind the selected tab, whose symbol and title take the tint color.


**Bottom accessory and minimizing.** `tabViewBottomAccessory` and `tabBarMinimizeBehavior` write
environment values that the tab view reads. The accessory is a `TabViewBottomAccessory` node, a
child of the `TabView` before its `TabBar`, evaluated with
`tabViewBottomAccessoryPlacement` set to `.expanded` or `.inline` and drawn as a glass capsule
(`BottomAccessory.swift`). Open, it is 48 points high and 8 points above the bar, as wide as the
bar; the content of a scroll view ends above it. The sizes are assumed, since the design export is
not available. `.automatic` is `.never`, as on iPhone.

The minimized state is host state (`ScrollLayout.tabBars`, `TabBarMinimize.swift`). After each
layout, `LayoutEngine.updateTabBarMinimization` compares the offset of the scroll view under the
bar with its offset at the last layout: with `.onScrollDown`, a move down minimizes and a move up,
or the top, restores (`.onScrollUp` is the reverse). A change makes `ViewHost.relayout` evaluate the
tree again with the new state, animated, so the accessory sees its new placement. A minimized bar
is a 64 × 48 capsule at the leading end with only the selected tab's symbol; the accessory fills
the row beside it. Tapping the capsule restores the bar. Only a tab whose content is one scroll
view, alone or in a navigation stack, can minimize.
### Presentations

A sheet, full-screen cover, or alert is a modifier that registers a presentation with the
evaluator while it is presented; an open menu picker registers a menu the same way. After the main tree, the host evaluates each presentation's
content, which can present more, and adds it to the root of the tree as a `Sheet`,
`FullScreenCover`, or `Alert` node, in the order the views asked. Layout places these nodes on the
screen instead of in the root's implicit stack.

- **Identity.** Presented content is evaluated at the presenting view's path plus `sheet`,
  `sheet[<item ID>]`, `fullScreenCover`, or `alert`, so its state is separate from the presenting
  view's and is discarded when it is dismissed.
- **Input.** The last presentation is in front. `interactiveRoot` is that node, or the whole tree
  when nothing is presented, and every kind of input searches only there.
- **Layout.** A sheet's top is at the top of the safe area, or at its smallest detent; the
  medium detent's top is (screen height − safe-area top + 8) / 2, 451 of 956 points on an iPhone
  18 Pro Max with iOS 27.2. Below the large detent it is inset 8 points from the sides and the
  bottom, floats as glass that a grouped list's background lets show through, and its bottom
  corners follow the screen's, inset with it; a scroll view inside ends at the sheet's bottom.
  Its node records `detents` and `dragIndicator` when they are set, and the grabber draws in
  front of the sheet's content. An alert is 320 points wide, with its title and its message, in
  `subheadline` and a secondary gray, at the leading edge above capsule buttons: two side by
  side, and otherwise one above another with a cancel button last. Alert actions are evaluated
  with medium labels and draw as gray capsules whatever button style surrounds them.
- **Dismissal.** Dismissing sets the presenting binding back. A drag down on a sheet that no
  scroll view under the pointer can take moves the sheet, and a release beyond 100 points
  dismisses it. An alert's buttons dismiss it after their actions run. When a sheet leaves the
  tree, the host runs its `onDismiss`.

### Search

`searchable(text:placement:prompt:)` is a primitive view that returns a `Searchable` node: the content's
nodes, then a `SearchField` node (`Searchable.swift`, registered through the extension seam). Its layout
stacks the field and the content, the field first, or last for `placement=bottom`, so the field sits under
the navigation bar of a stack or a sheet, or above the tab bar in a tab with the search role. The field's
parts are ordinary views, so a `TextField` takes focus, typing, and `type_text`, and the bound text is the
text field's. `isSearching` is true in the content while the field has focus or the text is not empty; a
focus change in a search field marks the host as needing an update, because focus is not state.
`dismissSearch` clears the text and ends editing. Assumed, since no source covers it: the heights of 36
points at the top and 48 at the bottom, the bottom field's glass capsule, a placement other than the
automatic or toolbar one in a search tab staying at the top, and a Cancel button only at the top. Selecting
a search tab does not focus its field, as it does on iOS, so an agent focuses the field before `type_text`.

### The environment

`EnvironmentValues` flow down through evaluation. The evaluator holds the current values,
`environment(_:_:)` changes them for its content, and an `@Environment` property reads them when
the evaluator installs a view's dynamic properties. Presented content and pushed views get
`isPresented` and a `dismiss` action that sets their binding back or pops them. Other built-in
values arrive with the modifiers that read them.

`environment(_:)` places an observable object in the environment by its type, and
`@Environment(Model.self)` reads it; reading one that no view above placed stops the app, as in
SwiftUI. The values that views commonly read describe the simulated iPhone: `colorScheme` and
`dynamicTypeSize` are the host's settings, `light` and `large` by default, the size classes are
compact across and regular down, and `locale` is US English.

### Appearance

`ViewHost.colorScheme` and `ViewHost.dynamicTypeSize` are the simulated device's settings, as in
its Settings app; setting either updates the tree. They start the root environment, and the
root records them when they are not `light` and `large`
([ADR 0009](adr/0009-appearance-in-the-tree.md)).

- `environment(\.colorScheme, _:)` and `dynamicTypeSize(_:)` change the environment of their
  content like any other value. Every environment writer compares the two values before and after
  its change and records a changed one on the nodes it returns, unless a writer inside already
  recorded its own, so the tree says where each scheme and size begins.
- `preferredColorScheme(_:)` is a preference, which flows up. The evaluator keeps one slot for
  the presentation being evaluated: the window, then each sheet, alert, or menu in turn. A
  modifier evaluates its content with an empty slot, then fills the enclosing slot with its own
  value, or else its content's, unless an earlier sibling filled it first. The host keeps each
  presentation's preference by its identifier and starts that presentation's content in the
  scheme it preferred last time. When a pass finds a different preference, the host evaluates
  again, through the bounded update loop, so views before the modifier see the scheme too. A
  presentation without a preference starts in its presenter's scheme, and a presentation node
  records `colorScheme` when its scheme differs from the window's.
- The preview window, web pages, and `parhelion mcp` switch the settings with
  `PreviewCommand.setAppearance`, which an app accepts when its hello lists the `appearance`
  capability. The tool keeps the setting and passes it to each launch as
  `PARHELION_COLOR_SCHEME` and `PARHELION_DYNAMIC_TYPE_SIZE`, so it survives hot reload.

### Lifecycle and tasks

`onAppear`, `onDisappear`, `onChange(of:)`, and `task` record themselves with the evaluator as
they are evaluated, outermost first, keyed by structural position and their order there. After
each update, the host compares the records with the last update's:

- A view is on screen when one of the nodes it resolved to is in the tree. Screens beneath the
  top of a navigation stack are evaluated but not in the tree, so a push makes the screen beneath
  disappear, and a pop makes it appear again.
- The host cancels the tasks of views that left, starts the tasks of views that arrived, and
  restarts a `task(id:)` whose id changed. Then it runs `onDisappear`, `onAppear`, and
  `onChange` actions, in that order. Assumed: SwiftUI does not document this order.
- An action that changes state starts another update, up to `ViewHost.maximumUpdatePasses` in a
  row. If state is still changing then, as when an `onChange(of:)` action changes the value it
  watches, the host writes one warning that names the actions of the last update, and stops
  until the next change, so that a preview session does not update on every turn of its loop.
- Tasks run on the main actor. Cancelling a task asks it to stop, as Swift's cancellation does;
  a cancelled run keeps going until it returns, and its changes apply like any other, though
  `@State` of a view that left went with the view. `pendingTaskCount` counts every run that
  has not returned, cancelled or not, and `waitForTasks()` waits until there are none, updating
  the tree as they change state, so no task changes state after it returns. Tests await it;
  agents see the count in every reply.
- `AsyncImage` loads in a `task(id:)` of its own, keyed by its URL and scale, so its load counts
  like any other task. It reads `file:` URLs from disk and others with `URLSession`, decodes PNG
  data off the main actor into `ImageLibrary` by URL, and keeps the phase in `@State` with the
  URL it belongs to. Its node is `AsyncImage` with the `url`, `phase`, and `scale`, and its
  content as children.

### Animation

`ViewHost.root` always holds final values: when a change animates, the tree, hit testing, and
everything agents read show where views end up. The renderer draws `presentedRoot`, which is
`root` with the animations in progress applied, the way Core Animation separates the model layer
from the presentation layer ([ADR 0005](adr/0005-model-tree-and-presented-frames.md)).

- **Starting.** After each layout, `AnimationEngine` compares what was on screen with the new
  tree. A node whose position, size, or opacity changed animates if an `animation(_:value:)`
  around it saw its value change, or else if the change happened inside `withAnimation` or a
  navigation push or pop. Sheets and alerts always animate.
- **Relative motion.** A position is animated relative to the node's parent, so content moving
  with its parent needs no animation of its own, and a change that is not animated, such as a
  scroll, still moves animated content correctly. Text keeps its final size while it moves, so
  it does not rewrap.
- **Transitions.** The topmost node of a new subtree enters with its transition, by default a
  fade. The topmost node of a removed subtree is kept, as last drawn, until its transition ends.
  Screens of a navigation stack slide across the stack; sheets move up from the bottom edge.
- **Matched geometry.** `matchedGeometryEffect`, `matchedTransitionSource`, and the zoom
  `navigationTransition` are modifiers that stay in the tree as data, with the namespace and the
  ID (`MatchedGeometry.swift`). After the rest of an update, `AnimationEngine` pairs each view that
  arrives with a view of the old tree that has the same namespace and ID (one that left first, then
  a source, then any) and gives it a displacement from that view's frame, less what its ancestors'
  entrances already move it, so a view that arrives inside a sheet still starts at the matched frame.
  A view that left and sits at the top of its removed subtree moves to the new frame while it fades;
  a matched view deeper inside one fades with its parent. A full-screen cover or pushed screen that
  contains a zoom transition replaces its slide with a zoom: the node keeps its final size, and the
  presented tree gives it the rectangle between the source's frame and its own as a `scaleEffect`
  about its top leading corner, so that its content scales too. Content fades in over the first 40%
  of a zoom and out over the last 40%.
- **Time.** Curves are evaluated at the host's `time`, so the frames depend only on the changes
  and when they happened. `isAnimating` stays true until every animation has ended, and each
  `advanceTime(by:)` call while one runs increases `revision`, so the preview session draws a
  frame for every display refresh. Springs end when they settle within a thousandth of their
  target.

### Text input

A `TextField` registers its binding with the evaluator, the way a `Button` registers its action.
`ViewHost` keeps the focused field and the caret offset, in characters:

- `focus(_:)`, a click on a field, or Tab and Shift-Tab choose the field. A click places the
  caret at the nearest character boundary.
- `typeText(_:)` inserts at the caret and writes through the binding, so the bound `@State`
  changes and the tree updates.
- `press(_:)` applies `ViewHost.Key` editing keys: Backspace, Delete, Left, Right, Home, End, and
  Return or Escape to end editing.

`TextField(_:text:axis: .vertical)` wraps its text at the field's width and is as tall as its
lines, between one line (or the range's lower bound) and the `lineLimit`. Past the limit, the
lines scroll so that the caret's line is the last one shown. `VerticalFieldGeometry` breaks the
value into lines that remember where they start, and layout, drawing, clicks, and the caret keys
share it. In such a field, Return inserts a new line instead of ending editing, Up and Down move
the caret between lines, and Home and End go to the start and end of the caret's line.

The window host turns SDL3 text input events into `text` messages, after keyboard layouts and
input methods, and key events into `key` messages. A field is one line tall and fills the width
it is offered. It draws its text, or its placeholder in the tertiary color, shifts the text left
to keep the caret in view, and draws a caret in the tint color while focused.

**Selection and the pasteboard.** The host keeps a selection anchor beside the caret
(`ViewHost.selectedRange`): the selection is the characters between them. Dragging over a field
anchors at the press and follows the pointer; `selectLeft`, `selectRight`, `selectHome`,
`selectEnd`, and `selectAll` move the caret and keep the anchor; a plain arrow key collapses the
selection to its edge. Typing, Backspace, Delete, and paste replace the selection. The renderer
draws the selection as the tint color at 25% behind the text, and the cache keys include the
anchor. The host also has a pasteboard of text (`ViewHost.pasteboardText`), which `copy` and `cut`
fill, `paste` inserts (line breaks become spaces, as in a one-line UIKit field), and `PasteButton`
reads: a `PasteButton` is a `Button` in a `PasteButton` node, disabled while the pasteboard has
nothing of its type. The `pasteboard` capability connects it to the window: the window hook sends
`paste` with the system clipboard's text on Control-V and `pasteboard` when the window gains
focus, and the app sends `pasteboard` when it copies, which the window puts on the system
clipboard. The `set_clipboard` tool and `PreviewCommand.setPasteboard` fill it for agents. The web
preview does not pass clipboard keys yet.

### Controls

`Toggle`, `Slider`, `Stepper`, `Picker`, and `LabeledContent` are primitive views whose parts are
nodes of their own, so that every part a person can press has a frame and an identifier. The
sizes and colors come from Apple's iOS 27 UI Kit. Layout and drawing for them live in
`LayoutEngine+Controls.swift` and `Rendering+Controls.swift`, which the layout engine and the
renderer call for the kinds they do not handle themselves.

- **Rows.** A toggle, a stepper, labeled content, and a menu picker with a label fill the width
  they are offered, with the label at the leading edge and the control at the trailing edge. In
  a list, a row that holds a switch, a stepper, or a segmented control gets smaller vertical
  insets, so it stays 52 points tall, as in the kit. `Form` is an inset grouped `List`.
- **Parts that respond.** A toggle's `Switch`, a stepper's two `StepperButton` halves, and a
  picker's `PickerOption` nodes and `PopUpButton` register actions as buttons do, and carry a
  `label` attribute or text, so `tap(_:)`, `tapButton(labeled:)`, `tap(at:)`, and the pointer
  methods all reach them. `tapButton(labeled:)` matches any node with an action.
- **Sliders** follow a press instead of a tap. A slider keeps its binding and range in host
  storage under its `SliderTrack`, which outlives an update; `pointerDown` takes the knob before
  the press can become a scroll, `pointerMoved` moves it, and `pointerUp` and `tap(at:)` move it to
  the point.
- **Animation.** A switch's knob and a segmented picker's selection capsule animate with an
  implicit spring when the value changes, so content that depends on the value changes at once,
  as in SwiftUI. A switch's track color follows its knob as drawn.
- **Menus.** An open menu picker presents a `Menu` node at the root, like an alert, which is
  placed level with its button after everything below it is placed. While it is open it is the
  `interactiveRoot`; its node covers the screen and closes the menu when a tap misses its items.
- **`Menu` and `contextMenu`.** A `Menu` is a `Button` node with `menu=true`, so button styles
  apply; the node kind `Menu` is already the open menu picker's panel, which is why the button does
  not use it. Opening it registers a `MenuPopover` presentation holding a `MenuPanel`: the content's
  `Button`s, `Section`s, `Divider`s (`MenuSeparator`), and `ControlGroup`s, with a separator
  inserted around each section and group. `contextMenu` puts a long press handler on its content's
  nodes; the long press registers a `ContextMenu` presentation with a `ContextMenuPreview`, a copy
  of the view (or its `preview`) scaled to 1.03 over a blur of the screen, and a `MenuPanel`.
  All of these register through `NodeExtensions` in `Rendering+Menu.swift`. A tap on an item runs
  its action, then closes the menu; a tap outside closes it. Menus fade in like sheets, so a test
  that renders one calls `advanceTime(by:)` first.
- **Pull to refresh.** `refreshable(action:)` sets the `refresh` environment value and marks each
  vertical `List` and `ScrollView` in its content `refreshable=true`, with the action in the
  node's input handlers; a nearer modifier wins. Dragging such a scroll view down from its top
  keeps the finger's travel in `ScrollLayout.refresh`, and the content follows at half the
  distance: layout adds that distance to the scroll view's top inset, and the renderer draws the
  spinner in the gap. Releasing at 60 points or more starts the action with `ViewLifecycle.track`,
  so `waitForTasks()` and `pendingTaskCount` include it, and holds a 52-point gap, with the node
  attribute `refreshing=true`, until the action returns. The spinner's head turns with the host's
  clock.
- **Tags.** `tag(_:includeOptional:)` records a value that `Evaluator.evaluateTagged` returns to
  the container evaluating the content, such as a picker. Inside such a container, `ForEach`
  tags its elements' views with their identifiers.
- **`disabled(_:)`** turns off `EnvironmentValues.isEnabled`. Controls, buttons, links, and text
  fields under it register no actions, record `disabled=true`, and draw dimmed.

### Accessibility

`accessibilityIdentifier(_:)`, `accessibilityLabel(_:)` (a string or a `Text`), and
`accessibilityElement(children:)` record the attributes `accessibilityIdentifier`,
`accessibilityLabel`, and `accessibilityElement` (`ignore`, `combine`, or `contain`) on the nodes
the view resolves to, so `outline()` and the JSON tree show them. Lookups follow SwiftUI's rules,
which `ViewNode.accessibilityEntries()` applies in one pass:

- An identifier on a view that is not an element, such as a stack, passes down to the views
  inside it and replaces theirs. `accessibilityElement(children: .contain)` makes the view an
  element whose children keep their own identifiers.
- The children of an `.ignore` or `.combine` element, and of a control such as a button, belong
  to that element and are not found by identifier on their own. Assumed, not documented by
  Apple: a control with no identifier takes the first one set inside its label.
- `ViewNode.label` prefers `accessibilityLabel`, so `tapButton(labeled:)` and the `tap` tool's
  `label` match accessibility labels, as XCUITest does. An `.ignore` element reads only its
  label; a `.combine` element joins its children's labels with `", "` (Apple does not document
  the separator).

`ViewHost` taps, focuses, and scrolls by identifier. A node that is not the kind of view the
action needs, such as a toggle whose switch is inside it, stands for the views of that kind
inside it. Several candidates are an `InteractionError.ambiguousAccessibilityIdentifier` that
lists them, as XCUITest's `element` fails on several matches. The MCP tools `tap`, `type_text`,
and `scroll_to` take `accessibility_identifier` for this, and the app accepts the matching
`PreviewCommand`s when its hello lists the `accessibilityIdentifiers` capability.

### Interaction

`ViewHost` delivers taps by node identifier (`tap(_:)`), by accessibility identifier
(`tap(accessibilityIdentifier:)`), by label (`tapButton(labeled:)`), or by
screen position (`tap(at:)`). A tap at a position goes to the frontmost node with an action whose
frame contains the point, or moves a slider's knob there. Every failure is a typed
`InteractionError` that names the problem, so an agent can recover without parsing messages.
Every method that delivers input, and every command from an agent, first updates the tree if
state changed since the last update, so input reaches the views on screen now, even after a task
or another thread changed state.

### The preview window

The window is a separate process ([ADR 0004](adr/0004-pure-swift-renderer.md)):

```text
 parhelion preview (SDL3)                    the app (ParhelionUI)
 ┌───────────────────────┐   hello, frames   ┌─────────────────────────┐
 │ window, texture,      │ ◄──────────────── │ ViewHost: evaluate,     │
 │ mouse events          │ ────────────────► │ layout, render to RGBA  │
 └───────────────────────┘   pointer input   └─────────────────────────┘
          Unix domain socket, path in PARHELION_PREVIEW_SOCKET
```

1. `parhelion preview` listens on a socket and starts the app with the socket's path in
   `PARHELION_PREVIEW_SOCKET`.
2. `App.main()` sees the variable, connects, and runs a `PreviewSession` instead of the headless
   runner. It sends a hello message with the screen size, then a frame.
3. The host opens a window of the screen's size in points, shows each frame as a texture, and
   sends mouse presses, moves, and releases back in points.
4. The session applies the input to `ViewHost` and sends a new frame whenever the screen
   changes. Closing the window sends `close`, and the app exits.

Messages are length-prefixed: a 4-byte length, a 1-byte kind, and a payload. Control messages are
JSON; frames, ticks, and slot releases are binary. The receiver reads the 5-byte header, then
exactly the payload, straight into the array the message keeps. Set `PARHELION_DEBUG=1` to trace
events, messages, render, transport, upload, and present times in both processes.

**Capabilities.** The hello lists the optional parts of the protocol the app supports, and a host
that supports them too answers with `welcome`. Only then does either side use them, so apps and
hosts from before a capability keep working with newer ones
([ADR 0006](adr/0006-host-clock-and-shared-frames.md)):

- **`hostClock`: the host owns the clock.** The window host turns on vsync and reads the
  display's refresh rate, again when the window moves to another display. While the app reports
  that something moves, the host presents once per refresh and sends `tick`s whose target is the
  moment the frame will be on screen. Times are nanoseconds of
  `CLOCK_MONOTONIC`, which both processes share (`PreviewClock`). The app advances its clock to
  the target and draws once; input that arrives in between changes state and is drawn on the next
  tick. The host waits for that frame until shortly before the refresh, so a frame that misses
  it is shown one refresh later and the previous frame stays up meanwhile. As soon as an answer
  arrives, the host sends the next tick, so the app draws the next frame while the host uploads
  and presents this one, at most two frames ahead of the screen
  ([ADR 0020](adr/0020-overlapped-frames.md)). An app too slow on average for every refresh is
  shown every second, third, or later refresh, evenly (`FramePacer`). The app is
  also shown no faster than the simulated screen's `maximumFramesPerSecond`, which the hello
  carries: on a 240 Hz display, each frame of a 120 Hz iPhone stays up for two refreshes, and a
  frame that arrives early waits until shortly before the refresh it is due at. On a display
  whose rate is not a multiple of the screen's, the app runs slower than the screen, never
  faster: 72 Hz on a 144 Hz display for a 120 Hz screen. If vsync
  is refused or presents return without waiting, the host waits for each refresh itself. When
  nothing moves, the host blocks on window events and the app on the socket.
- **`sharedFrames`: frames in shared memory.** The app creates an anonymous file with three
  frame-sized slots and passes its descriptor to the host once, with `SCM_RIGHTS`. A frame is then
  a `frameUpdate` message that names a slot, the damaged rectangle, whether the app is animating,
  and the tick it answers. The host uploads from the slot and sends `releaseSlot`. Without a free
  slot, the pixels travel in the message.
- **`appearance`: the appearance switches.** The app takes `setAppearance` commands. The host
  reads this one in the hello and sends no welcome for it, so `parhelion mcp` without a window,
  which welcomes nothing, can switch it too.
- **`accessibilityIdentifiers`: views by accessibility identifier.** The app takes
  `tapAccessibilityIdentifier`, `focusAccessibilityIdentifier`, and
  `scrollToAccessibilityIdentifier` commands. Like `appearance`, the host reads it in the hello.

- **`manualClock`: the host moves time.** An app started with `PARHELION_MANUAL_CLOCK=1` lists
  it, and a host that shows no frames (`parhelion mcp` without `--window` or `--web`) welcomes it
  ([ADR 0012](adr/0012-manual-clock.md)). The app then never reads the real clock and never
  draws on its own schedule. `advanceTime(seconds:)` moves `ViewHost.time` and the executors'
  clock together, waking each `Task.sleep` in deadline order and settling the app after each. At
  start, `App.main()` replaces Swift's main and default executors (`HostClockExecutor`, Swift 6.3
  and later, SPI), which hold sleeps and run all work serially on the main thread. MCP `wait`
  sends the command, so it returns at once. The reply's `nextWake` is the time to the next held
  sleep.

**Main-actor work.** The app receives the host's messages on a background thread. Its main
thread waits in the main run loop, so the main actor's work runs while nothing arrives: `task`
actions, `Task`s that buttons start, and changes to models made on other threads. When that work
changes state, the session updates and sends a frame, as it does after input, before it applies
the next message. (A session that a
test runs on the main actor cannot run the main queue from inside it, so it only waits for
messages.)

An app that is not welcomed sends plain frames and keeps its own schedule: 60 frames per second
on a fixed grid, with the clock moved to the current time before each frame. A welcomed app
returns to that schedule if ticks stop for 100 ms. Agent screenshots are separate from frames:
they are PNG data in command replies.

Pointer input follows iOS: a press on a button highlights it, moving off the button cancels the
highlight, and releasing over the same button taps it. `ViewHost.pointerDown(at:)`,
`pointerMoved(to:)`, and `pointerUp(at:)` implement this for every client, not only the window.

### The web preview

`--web` shows the same session on web pages instead of, or with `parhelion mcp --window`, as
well as the window:

```text
 browser                     parhelion                              the app
 ┌──────────────┐ WebSocket  ┌──────────────────────────┐  socket,   ┌──────────────┐
 │ canvas,      │ ◄───────── │ WebPreview: frame copy,  │ ◄───────── │ ViewHost     │
 │ bezel image, │ ─────────► │ one sender per page;     │ ─────────► │              │
 │ input        │ input JSON │ FrameLoop + WebHost      │  ticks     └──────────────┘
 └──────────────┘            └──────────────────────────┘  shared memory
```

**The frame loop's surface.** `FrameLoop` drives a `PreviewSurface`: something that collects
input, takes frames, and presents. The SDL window is one. `WebHost` is another, with no vsync and
a refresh period of one frame of the simulated screen, from the hello's
`maximumFramesPerSecond`, so the pacer's timer path ticks the app at the device's rate: a browser
has no vsync to follow. `MirroredSurface` combines the window and the web host for
`parhelion mcp --window --web`: the window paces, and pages get every frame it shows. Control-C
and `SIGTERM` close a web-only session the way closing the window does.

**The server.** `WebServer` in `ParhelionTooling` is a small HTTP/1.1 and WebSocket (RFC 6455)
server over POSIX sockets, with no dependencies and a thread per connection. It serves three
paths: the page at `/`, the bezel as a PNG at `/bezel.png`, drawn by `DeviceBezel` once per app,
and the WebSocket at `/socket`. The page is Swift source, `WebPage.swift`, because Parhelion ships
no resources ([ADR 0003](adr/0003-no-swiftpm-resources.md)).

**Access.** Anyone who can open the page controls the app. The server binds 127.0.0.1 unless
`--web-address` names another address, and every request must carry the 128-bit random token in
the printed URL as its `token` parameter. The server checks it, in constant time, before it
looks at the path, so the page, the bezel, and the WebSocket handshake all answer 403 without it.
Responses are not cached and send no referrer, the page's content security policy loads no
script, style, or image from elsewhere, and the server limits request heads to 16 KB and 10
seconds and serves 32 connections at most. Pages may send only input, acknowledgements, and a
named color scheme or text size from the page's controls, which the tool keeps for every page and
the window and passes to the app. The input is pointer down, move,
and up, scroll, text, and the editing keys, each checked before it becomes a `HostMessage`.

**Frames.** The web host copies each frame's damaged rows from the shared-memory slot into a
`FrameBuffer`, which releases the slot at once, and adds the damage to each page's pending
rectangle when it presents. Each page has a sender thread. It sends the pending rectangle when
the page has fewer than three frames unacknowledged, and the page acknowledges a frame once it
has drawn it. A page on a slow connection therefore gets fewer frames, each with everything that
changed since the last, never a growing queue.

A frame message is a list of parts that the page applies in order. The host keeps a copy of
what each page shows (`PageImage`) and compares the rectangle's rows with it, by CRC-32 and then
byte for byte:

- Rows that did not change are not sent.
- When most changed rows match rows some distance away, as when content scrolled by whole pixels,
  a copy part moves them within the page's canvas.
- The remaining rows go as pixels in runs of up to 256 rows, compressed with zlib at level 4, in
  parallel. The page decompresses them with `DecompressionStream` in up to four workers, or
  itself until the workers answer a first small stream, and draws them with `putImageData`.

zlib is loaded with `dlopen` when first used, so building the tool needs no zlib headers; without
it, pixels go uncompressed.

**Measurements.** A fling in the `Scrolling` example on iPhone 16 (60 Hz, 786 × 1704 pixels at
2×) changes about 1,250 of the 1,704 rows in each frame, 5.4 MB uncompressed. Measured in
headless Chromium on a 12-core desktop with other builds running, with a release build of the
tool:

| Link | Frames per second | KB per frame |
| --- | --- | --- |
| localhost | 53 to 59 | 34 to 39 |
| 50 Mbit/s, 20 ms round trip | 59 | 36 to 38 |
| 20 Mbit/s, 40 ms round trip | 36 to 37 | 33 |
| 10 Mbit/s, 60 ms round trip | 22 to 25 | 35 |

On iPhone 16 Pro (120 Hz) on localhost, the page shows 102 to 107 frames per second; drawing in
the page, about 8 ms a frame without a GPU, is the limit. The host encodes a frame in 2 to 4 ms.
Before the row comparison and level 4, whole damaged rectangles at level 1 cost 62 KB a frame,
and the 20 Mbit/s link showed 26 frames per second. On these rows, level 4 makes 20% fewer bytes
than level 1 for about three times the time: 37.5 KB in 4.8 ms against 46 KB in 1.6 ms with
zlib-ng, and 37.5 KB in 6.2 ms against 53 KB in 2.5 ms with classic zlib. Filtering the rows as
PNG does, or subtracting the previous frame, made them larger.

Copy parts help only when content moves by whole pixels. While a finger drags a list they cut a
frame to 4 to 8 KB, but momentum scrolling moves content by fractions of a pixel, the
anti-aliased rows never match exactly, and every changed row is sent.

**Hot reload.** The server lives in the tool, not the app, so a page stays connected while the
app restarts. A new app's hello reaches pages only if it differs from the last, and its first
frame sends pages whatever changed. Pages show the build's progress and errors as the window
shows them in its title.

### Hot reload

`parhelion run` keeps one window open across many runs of the app:

1. It reads the package with `swift package dump-package`. An executable product or target is
   built as it is. A library product, the shape `xtool new` creates, is built through a runner
   package generated in `.build/parhelion-runner`: an executable target whose source directory
   is a symbolic link to the app's target, with the same dependencies. The app's `@main` type
   becomes the entry point.
2. It builds, starts the app with `parhelion preview`'s protocol, and watches the package's
   Swift files with inotify, one watch per source directory, so a save is seen within a
   millisecond. Where inotify is missing or out of watches, it compares modification times twice
   a second instead. A `parhelion.json` in the package can add more paths to watch, such as
   Rust crates, which are watched for every file and not only Swift files.
3. On a change, it rebuilds on a background thread while the window keeps showing the running
   app. If the build fails, it prints the errors, with runner paths mapped back to the app's
   files, and leaves the app running.
4. If the build succeeds, it sends `close`. The app writes `ViewHost.stateSnapshot()` to the file
   named in `PARHELION_PREVIEW_STATE` and exits. The host starts the new build with the same
   variable, and the new `ViewHost` restores each `Codable` state whose structural position and
   type still match. An `@Observable` model is kept the same way when it is `Codable` and is held
   in `@State`, in a view or in the app; models elsewhere start over. When the new app's first frame is on screen, the tool prints the time from
   the change, split into build and restart.

**Build mode.** A debug build compiles the app at `-Onone`, so an edit rebuilds incrementally in
about a second, and Parhelion's own modules optimized, so a frame renders in about 2 ms instead of
15. Parhelion's manifest adds `-O` to its targets in debug builds on Linux only while
`PARHELION_OPTIMIZE_FRAMEWORK=1` is set, and `AppBuilder` sets it. SwiftPM rejects unsafe flags in
a dependency pinned to a version, so for such apps the tool builds everything with
`-Xswiftc -O` instead, which optimizes the app too. Builds go to `.build/parhelion` in the package
that is built, so turning the variable on or off and the user's own `swift build` never
invalidate each other's products. `-c release` builds everything optimized, in the same
directory. The tool prints which mode it uses, and the modules each rebuild compiled.

The tool's logic lives in `ParhelionTooling`, a library with tests, separate from the SDL code.

### The agent server

`parhelion mcp` serves one app to a coding agent over the Model Context Protocol, on standard
input and output:

```text
 agent  ◄── MCP, JSON-RPC lines ──►  parhelion mcp  ◄── commands, replies ──►  the app
                                     (optional window)     Unix domain socket
```

1. It builds the app the way `parhelion run` does and starts it with the preview protocol, with
   the app's output captured, because standard output carries the protocol.
2. Each tool call becomes a `command` message with a request identifier. The app runs it on
   `ViewHost` with `execute(_:)` and answers with a `reply`: whether it succeeded, a message for
   the agent, an optional PNG, the screen's `revision`, and whether scrolling is still animating.
3. `rebuild` builds again from the current sources. If the build succeeds, it restarts the app
   with its state, as hot reload does. If the build fails, the old app keeps running and the
   tool result is the compiler errors, as plain text with paths to the app's own files.

Every reply also says whether anything is animating and how many `task` actions are running.
The `wait` tool returns as soon as both are done, or after the time the agent gave; when nothing
was running to begin with, it waits the whole time, so untracked work has time to run.

A failed tool call is a result with `isError`, so the model reads the message and tries again.
Only malformed requests are JSON-RPC errors. With `--window`, the same app also appears in a
preview window: the protocol moves to a background thread, SDL keeps the main thread, and
frames and mouse input flow as in `parhelion run`. A person and an agent then use one app.

`compare_image` takes a design board PNG, a screenshot of the whole screen at a whole scale such
as 3×, finds the scale from its width, asks the app for a screenshot at that scale, and compares
the two with `ImageDiff` in `ParhelionTooling`: a pixel differs when any of its red, green, blue,
or alpha values is more than the tolerance (8 of 255 by default) from the board's. The result is
the share of differing pixels and the area they lie in, with a diff PNG, the screenshot faded
with the differing pixels in red. `parhelion run --overlay` draws the board over the window's
screen, under the bezel, as a texture with an opacity.

The screenshot tool is the off-screen rendering path: any process that speaks the socket
protocol can request frames and send input without a window.

### Recorded flows

A `Flow` (in `ParhelionPreview`, so the tool and the app share it) is a recorded run: a `version`
(the file's own format, apart from the protocol's), the `device` name, and `steps`. A step is
`command(PreviewCommand)`, `wait(seconds:)`, or `expect(outline:)`. The file is indented JSON with
sorted keys; a checkpoint is a list of lines, so changes read well in a diff, and commands are the
`PreviewCommand`s the agent tools send, so an agent can write a flow too.

```text
 window ── pointer, text, key, F2 ──►  app (PreviewSession)  ──►  FlowRecorder ──► FLOW.json
 parhelion test ── replay(flow) ──►  app (manual clock)  ──►  ViewHost.replay ──► FlowReport
```

**The app records, not the window host**, because only the app knows which control a release hit.
`parhelion run --record FILE` sets `PARHELION_RECORD_FLOW` for the first launch. `PreviewSession`
calls `FlowRecorder` around each input it applies, because a tap is named from the screen as it was
before the tap ran. A press that moved more than the drag threshold becomes `drag`; a release on a
control becomes a tap that names it by accessibility identifier if that finds only it (the lookup a
`tapAccessibilityIdentifier` command makes), else by label if exactly one control has it, else by
node identifier. A slider is recorded by its point, since no command names a knob position. A
text field is focused by identifier or node identifier, which puts the caret at the end. Wheel
events and typing without a pause between them merge into one `scroll` or `typeText`. The real time
between steps becomes `wait` steps: pauses under 50 ms are dropped, and one step waits at most 10 s.
The flow is written after every step, and the window's F2 key sends `HostMessage.checkpoint`.
Assumed, since no source covers it: F2 is the checkpoint key, a reload ends the recording, and the
file ends with a checkpoint when the host closes the app.

**`ViewHost.replay(_:updatingCheckpoints:)` is the one engine.** It runs commands with `execute`,
moves the clock for waits with `advanceClock(by:)`, and compares `root.outline()` without
identifiers or frames at checkpoints; frames would fail on every layout tweak. It stops at the
first failing step and returns a `FlowReport` with the step, the message, and a line diff. With
`updatingCheckpoints`, differing checkpoints are rewritten and returned in `updatedFlow`.
`parhelion test` starts a fresh app for each flow on the flow's device with `PARHELION_MANUAL_CLOCK=1`,
sends one `replay` command, and prints the report; a Swift Testing test calls `replay` directly, on
the real clock. An app lists the `flowReplay` capability when it takes `replay` and
`checkpoint`.

### Extension points

A new view kind, layout modifier, MCP tool, or window hook plugs in from its own file
([ADR 0011](adr/0011-extension-seam.md)):

| What | How it registers | Where it is consulted |
| --- | --- | --- |
| A view kind | `NodeExtensions.registerOnce(kind:)`, called when its primitive view makes its nodes | Before the `switch node.kind` blocks of `LayoutEngine` (size, children, presentations) and `TreeRenderer.draw`, and in hit testing |
| A layout modifier | `customModifier(_:_:behavior:)` on `View`, which adds `LayoutModifier.custom` | The modifier switches of the layout engine, and `drawChain` for backgrounds, foregrounds, and wrapping effects |
| A long press or drag handler | `Evaluator.registerInputHandlers(_:for:)` | `ViewHost.longPress(at:duration:)` and `ViewHost.drag(from:to:duration:)` |
| An MCP tool | `AgentToolRegistry.shared.register(_:)` | `AgentTools.definitions` and `AgentController.handle` |
| A window hook | `WindowHookRegistry.shared.register(_:)` | `WindowHost.translate`, before the window's own meaning for an event |

A `NodeBehavior` has optional parts: `size`, `place`, `draw`, `hitTest`, and, for a presentation,
`isPresentation` and `placePresentation`. A part that is missing falls back to the default for
an unknown kind: a container that centers its children, drawing nothing. A `ModifierBehavior` can
change the size, change the rectangle of what it wraps, draw behind or in front, and draw what it
wraps through a function (`drawEffect`), which is how a modifier draws a layer of its own. The
modifier appears in the tree as a name and string parameters, so it stays data. A registered
kind or modifier is used wherever the built-in ones are: in the outline, in JSON, and in
snapshots.

A view and a modifier register themselves, because evaluating them runs the registration. An MCP
tool and a window hook are not evaluated, so something registers them once when the tool starts.

### Apps

`App`, `Scene`, and `WindowGroup` mirror SwiftUI so an app's `@main` type compiles. Under
Parhelion, `App.main()` runs a preview session when a window host started the app. Otherwise it
runs headlessly: it resolves the first window, lets `task` work finish for up to five seconds,
and prints the tree, or writes it to a PNG file with `--png`.

### Snapshot tests

`ViewHost.expectSnapshot(named:)` in `ParhelionTesting` renders the screen and compares it with a
PNG. It is the one place that imports `Testing`; `ParhelionUI` links into apps and does not.
`Snapshots.check` does the work and returns a `SnapshotOutcome`, so it is testable without
Swift Testing, and `expectSnapshot` turns the outcome into an issue.

- **Where references live.** `Tests/__Snapshots__/<test file>/<test>.<name>.png`, found through
  `#filePath`. The folder sits beside the test targets' folders, not in one: SwiftPM warns about
  unhandled files inside a target, and declaring them as resources is ruled out by
  [ADR 0003](adr/0003-no-swiftpm-resources.md). They are read at run time. A `reference:` URL
  replaces the path, which the README image tests use for `docs/images`.
- **The comparison.** Equal bytes pass without decoding. Otherwise both images are decoded with
  `Bitmap(pngData:)`, so a reference recompressed by another tool still matches, and
  `Bitmap.difference(from:channelTolerance:)` counts the pixels where any RGBA channel differs by
  more than `channelTolerance` (0 to 255). The test passes when the sizes match and that share is
  at most `pixelTolerance` (0 to 1). Both default to 0: renders were byte-identical across
  machines and build modes on x86-64 Linux. That is observed, not guaranteed; libm results can
  differ on other platforms, so set tolerances from measured diffs when another platform joins
  CI. The metric is integer arithmetic on purpose, because a perceptual one needs color
  conversion through libm, the source of the differences.
- **Failures.** The message gives the count, the largest channel difference, and the bounding box.
  The actual image and a diff image (differing pixels red over a faded copy) are attached; `swift
  test --attachments-path DIR` writes them, and without it they are discarded.
- **Record mode.** `PARHELION_RECORD_SNAPSHOTS` is `missing` (the default: write a reference that
  does not exist), `failed` (also rewrite those that do not match), `all`, or `never` (CI: never
  write). A write fails the test, so recording is never mistaken for passing. A value that is not
  a mode is an error, not a default.

### Gestures

`TapGesture`, `LongPressGesture`, `DragGesture`, and their combinations are recognized from the
host's pointer events and clock; [ADR 0015](adr/0015-gesture-arbitration.md) has the model. A
gesture modifier leaves a marker modifier named `gesture` on its nodes (the outline shows it, for
example `onTapGesture` or `gesture(drag)`) and registers a recognizer factory with the host. On
pointer down the host collects the gestures under the press and orders them: priority gestures,
then the deepest view first, with a button or text field after the gestures on its own view. A
recognizer that could still win holds back the callbacks of the ones below it, the first to be
recognized cancels the others, and a press turns into a scroll only when no gesture inside the
scroll view has it. `advanceTime(by:)` ticks the session, which is how a long press fires on the
manual clock. `ViewHost.longPress(at:duration:)` and the `long_press` MCP tool hold a press for a
duration; `ViewHost.drag(from:to:duration:)` and `drag` move it.

### Sensory feedback and Reduce Motion

Linux has no haptics, so `sensoryFeedback` records instead of playing. The modifier watches its
trigger the way `onChange(of:)` does (the first value is not a change) and, when the feedback
applies, appends a `SensoryFeedbackEvent` to the host's log: a sequence number, the feedback's
name (`selection`, `success`, `impact.medium`, `impact.heavy x0.5`), the node of the view, and the
host's time. The log keeps the last 50. The modifier marks its nodes with `sensoryFeedback=<name>`
(`dynamic` for the closure form, whose result depends on the values), and the root lists the
newest ten in its own `sensoryFeedback` attribute, so an outline shows what played. Recording marks
the host for one more update, which writes that attribute. `ViewHost.sensoryFeedbackEvents`,
`clearSensoryFeedback()`, the `sensoryFeedback(clear:)` preview command, and the
`get_sensory_feedback` MCP tool read it; `PARHELION_DEBUG=1` logs each event.

`ViewHost.reduceMotion` is the simulated device's Reduce Motion setting, like `colorScheme`. It
sets `accessibilityReduceMotion` for every view, presentations included, and the root records
`reduceMotion=true` while it is on. Parhelion does not change any animation by itself: as in
SwiftUI, a view reads the value and chooses. Four things set it: `PARHELION_REDUCE_MOTION=1` or
`--reduce-motion` at start, Control-Shift-M in the window (a `WindowHook`), `set_appearance` with
`reduce_motion` in `parhelion mcp`, and the `setReduceMotion` preview command. The tool keeps the
setting like the color scheme, so a rebuilt app starts with it. A separate command keeps
`setAppearance` as it was; an app lists the `accessibilitySettings` capability when it takes the
new commands, and the tool says so when an older app cannot.

### Scene phase

`ViewHost.scenePhase` is `active` by default and flows into the environment as
`EnvironmentValues.scenePhase`, for views and for an `App`'s own `@Environment`. Setting it updates
the tree, so each `onChange(of: scenePhase)` action runs once per change; the root records
`scenePhase=inactive` or `scenePhase=background` while the phase is not `active`. The phase moves
straight to the one set, where a phone passes through `inactive` on the way to `background`: set
`inactive` first to see that step. `Scene.onChange` puts its observer on the window's content, so
it does not change node identifiers. `PreviewCommand.setScenePhase` carries a phase to an app; the
`set_scene_phase` MCP tool sends it, and `ScenePhaseWindowHook` sends it when the window loses
focus (`inactive`), is minimized (`background`), or comes back (`active`).

### Media controls

`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`, in the `MediaPlayer` module, report the
app's now-playing state and take the desktop's play, pause, next, previous, and seek commands;
[ADR 0017](adr/0017-mediaplayer-mpris.md) has the decision. The shim turns each change of
`nowPlayingInfo`, `playbackState`, or a command's `isEnabled` into a `PreviewNowPlaying` and hands it to
`MediaSessionBridge.shared`. A session that the host welcomed with `PreviewCapability.mediaSession`
connects the bridge to its channel, so the state travels as `AppMessage.nowPlaying`. The host's
`AppConnection` gives it to an `MPRISService` (`ParhelionTooling`), which owns the connection to the
session bus and publishes `org.mpris.MediaPlayer2.parhelion.instance<pid>`. Calls on that player
return as `HostMessage.remoteCommand`, which the session passes to the bridge and the shim turns
into the events that the app's targets expect. A command the app did not enable falls back to the
nearest one it did: `play` and `pause` to `togglePlayPause`, and a relative seek to the skip
commands. Headless hosts (`parhelion test`, and `parhelion mcp` without frames) do not offer the
capability, so they never touch the bus.

### Audio session events

The `AVFAudio` module (Linux only) holds an `AVAudioSession` that does nothing except keep its
state and post notifications. `ViewHost.postAudioInterruptionBegan(reason:)`,
`postAudioInterruptionEnded(shouldResume:)`, and `postAudioRouteChange(reason:device:)`, which the
`audio_interruption` and `audio_route_change` MCP tools call through two `PreviewCommand` cases,
make the app's `AVAudioSession.interruptionNotification` and `routeChangeNotification` handlers
run, with Apple's user-info keys and types. [ADR 0018](adr/0018-audio-session-events.md) says how
the two modules meet without depending on each other.

## Planned layers

- **Fidelity checks.** A macOS CI job that renders the same views with Apple's SwiftUI and
  compares the resolved trees and layouts with Parhelion's.
