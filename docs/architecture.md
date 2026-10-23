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
| `parhelion` (in `Tools/parhelion-cli`) | Linux | The command-line tool and SDL3 window host. A separate package, because it depends on SDL3. |
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
writes through to the host-owned storage.

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
  There is no kerning, shaping, or tracking yet.
- **Fonts** flow down through the environment: `font(_:)`, `fontWeight(_:)`, and `bold(_:)` set
  them for their content, and `Text.font(_:)` overrides them. Each `Text` resolves its font when
  it is evaluated and records it as an attribute, such as `font=headline` or
  `font=largeTitle.bold`, unless it is the body style. Layout and drawing read only that
  attribute: a text style's size, line height, and weight come from `LayoutDefaults`, and the
  weight picks the nearest bundled Inter. Each line is the line height tall, with the difference
  from Inter's own height split above and below the glyphs, and the renderer draws with the same
  font and baselines so that layout and pixels agree.
- **The root** covers the device screen. Root content is proposed the safe area and centered in
  it. `Device.iPhone16` is the default; `PARHELION_DEVICE` picks another preset from
  `Device.all`.

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
  buttons; large glass for alerts and partial-height sheets. Before blurring, it checks whether
  the pixels the blur would read are one flat color, every row at one pixel per point, and then
  skips the blur and fills the shape with the tint blended over that color once.
- **Colors** come from `ColorPalette`, which maps SwiftUI's named colors and styles to iOS 27's
  light-appearance system colors. A `foregroundStyle` applies to the node and its descendants, and
  so does a `tint`. Button labels take the tint color unless they set their own style or their
  button style chooses another, and labels on glass are near-black.
- **Buttons** read a style, a control size, and where they are from the environment while they
  are evaluated, as `buttonStyle(_:)` and `controlSize(_:)` set them for all the buttons inside.
  A button records its style and size as attributes; layout makes a bordered or glass button a
  capsule around its label, and the renderer draws the capsule. A custom `ButtonStyle`'s body is
  evaluated in place of the label.
- **Backgrounds** fill the bounds at their position in the modifier chain. Each node records those
  bounds in `modifierFrames`.
- **Symbols** draw as placeholder rings until an open-source icon set replaces SF Symbols.
- **Rectangles**, most of what an interface draws, skip the general rasterizer: each pixel's
  coverage is its exact overlap with the rectangle, and fully covered runs are written as whole
  32-bit words. A typical screen renders in under 1 ms in an optimized build.
- **PNG** output uses a small built-in deflate encoder. A screen of mostly flat color compresses
  to about 50 KB at 2× scale.
- **Device chrome** draws over everything the app presents. `.systemBars` adds the status bar
  and the home indicator, which is what a Simulator screenshot shows; agent screenshots and
  `--png` use it, so every point of the image is a point on the screen. `.screen` also adds the
  Dynamic Island or notch and blacks out the screen's rounded corners; the preview session sends
  these frames. Each `Device` preset records its corner radius, cutout, and home indicator width.
  Parhelion draws only the light appearance so far, so the bars are always black. The status
  bar's clock uses Inter SemiBold in place of SF Pro. The chrome depends only on the device, the
  scale, and the kind of chrome, so `ViewHost` draws it once into a `CanvasOverlay` and blends
  that over each frame: opaque runs are copied as whole words, and only the anti-aliased edges
  are blended.
- **The bezel** exists only in the window. The window host draws the phone once, with a
  transparent hole the shape of the screen, and draws it over each frame. The window ends at the
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
moves (see *The preview window*). `ViewHost.revision` increases whenever the screen changes, and
the session sends a frame only then.

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
`.confirmationAction` gives its buttons the `glassProminent` style, and prominent buttons get a
capsule of their own nearer the edge, marked `glass=prominent`. Items are evaluated with medium
labels, and the renderer draws them near-black on glass.

The stack fills the space it is offered: the bar takes the top 54 points with an inline title,
or 105 with a large one, and the screen is centered in the rest, as root content is. Inside the
bar, the back button and the groups start 16 points from each edge, 12 points apart, and they
and an inline title center in the top 44-point row. A large title starts 54 points down, at the
leading margin, so the buttons stay above it. In a sheet the bar records `presentation=sheet`
and is 16 points taller, with the row 16 points below the sheet's top. A bar with principal
items or without a title always uses the inline layout.

### Presentations

A sheet, full-screen cover, or alert is a modifier that registers a presentation with the
evaluator while it is presented. After the main tree, the host evaluates each presentation's
content, which can present more, and adds it to the root of the tree as a `Sheet`,
`FullScreenCover`, or `Alert` node, in the order the views asked. Layout places these nodes on the
screen instead of in the root's implicit stack.

- **Identity.** Presented content is evaluated at the presenting view's path plus `sheet`,
  `sheet[<item ID>]`, `fullScreenCover`, or `alert`, so its state is separate from the presenting
  view's and is discarded when it is dismissed.
- **Input.** The last presentation is in front. `interactiveRoot` is that node, or the whole tree
  when nothing is presented, and every kind of input searches only there.
- **Layout.** A sheet's top is at the top of the safe area, or at its smallest detent; below
  the large detent it is inset 8 points from the sides and the bottom. Its node records
  `detents` and `dragIndicator` when they are set. An alert is 300 points wide, with its title
  and message at the leading edge above capsule buttons: two side by side, and otherwise one
  above another with a cancel button last. Alert actions are evaluated with medium labels and
  draw as gray capsules whatever button style surrounds them.
- **Dismissal.** Dismissing sets the presenting binding back. A drag down on a sheet that no
  scroll view under the pointer can take moves the sheet, and a release beyond 100 points
  dismisses it. An alert's buttons dismiss it after their actions run. When a sheet leaves the
  tree, the host runs its `onDismiss`.

### The environment

`EnvironmentValues` flow down through evaluation. The evaluator holds the current values,
`environment(_:_:)` changes them for its content, and an `@Environment` property reads them when
the evaluator installs a view's dynamic properties. Presented content and pushed views get
`isPresented` and a `dismiss` action that sets their binding back or pops them. Other built-in
values arrive with the modifiers that read them.

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

The window host turns SDL3 text input events into `text` messages, after keyboard layouts and
input methods, and key events into `key` messages. A field is one line tall and fills the width
it is offered. It draws its text, or its placeholder in the tertiary color, shifts the text left
to keep the caret in view, and draws a caret in the tint color while focused. There is no text
selection yet.

### Interaction

`ViewHost` delivers taps by node identifier (`tap(_:)`), by button label
(`tapButton(labeled:)`), or by screen position (`tap(at:)`). A tap at a position goes to the
frontmost button whose frame contains the point. Every failure is a typed `InteractionError` that names the
problem, so an agent can recover without parsing messages.

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
  that something moves, the host presents once per refresh and, after each present, sends a
  `tick` whose target is the moment the next frame will be on screen. Times are nanoseconds of
  `CLOCK_MONOTONIC`, which both processes share (`PreviewClock`). The app advances its clock to
  the target and draws once; input that arrives in between changes state and is drawn on the next
  tick. The host waits for that frame until shortly before the refresh, so a frame that misses
  it is shown one refresh later and the previous frame stays up meanwhile. An app too slow for
  every refresh is shown every second, third, or later refresh, evenly (`FramePacer`). The app is
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

An app that is not welcomed sends plain frames and keeps its own schedule: 60 frames per second
on a fixed grid, with the clock moved to the current time before each frame. A welcomed app
returns to that schedule if ticks stop for 100 ms. Agent screenshots are separate from frames:
they are PNG data in command replies.

Pointer input follows iOS: a press on a button highlights it, moving off the button cancels the
highlight, and releasing over the same button taps it. `ViewHost.pointerDown(at:)`,
`pointerMoved(to:)`, and `pointerUp(at:)` implement this for every client, not only the window.

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
   a second instead.
3. On a change, it rebuilds on a background thread while the window keeps showing the running
   app. If the build fails, it prints the errors, with runner paths mapped back to the app's
   files, and leaves the app running.
4. If the build succeeds, it sends `close`. The app writes `ViewHost.stateSnapshot()` to the file
   named in `PARHELION_PREVIEW_STATE` and exits. The host starts the new build with the same
   variable, and the new `ViewHost` restores each `Codable` state whose structural position and
   type still match. When the new app's first frame is on screen, the tool prints the time from
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

A failed tool call is a result with `isError`, so the model reads the message and tries again.
Only malformed requests are JSON-RPC errors. With `--window`, the same app also appears in a
preview window: the protocol moves to a background thread, SDL keeps the main thread, and
frames and mouse input flow as in `parhelion run`. A person and an agent then use one app.

The screenshot tool is the off-screen rendering path: any process that speaks the socket
protocol can request frames and send input without a window.

### Apps

`App`, `Scene`, and `WindowGroup` mirror SwiftUI so an app's `@main` type compiles. Under
Parhelion, `App.main()` runs a preview session when a window host started the app. Otherwise it
runs headlessly: it resolves the first window and prints the tree, or writes it to a PNG file
with `--png`.

## Planned layers

- **Fidelity checks.** A macOS CI job that renders the same views with Apple's SwiftUI and
  compares the resolved trees and layouts with Parhelion's.
