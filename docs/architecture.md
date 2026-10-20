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

Planned: hot reload and an agent server. See the [roadmap](roadmap.md).

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
  The widths are generated into source from `Fonts/Inter-Regular.ttf`, because Parhelion cannot
  ship SwiftPM resources ([ADR 0003](adr/0003-no-swiftpm-resources.md)).
  There is no kerning or shaping yet, and all text uses the body size until the environment and
  `font` exist. The renderer must draw with the same font file so that layout and pixels agree.
- **The root** covers the device screen. Root content is proposed the safe area and centered in
  it. `Device.iPhone16` is the default.

Every number in which Parhelion assumes SwiftUI's behavior, such as the default padding of 16
points, is in `LayoutDefaults.swift`. These are assumptions until the planned macOS fidelity job
verifies them.

### Rendering

`ViewHost.render(scale:)` draws the laid-out tree into a `RenderedFrame`, an RGBA image at the
given number of pixels per point. Like layout, the renderer reads only the tree.

- **Drawing** happens in `ParhelionRender`, a module with no dependencies. It parses Inter's
  TrueType outlines, flattens curves, and fills paths with exact-area anti-aliasing. There is no
  GPU and no system font library, so the same tree produces the same pixels on every machine
  ([ADR 0004](adr/0004-pure-swift-renderer.md)).
- **Colors** come from `ColorPalette`, which maps SwiftUI's named colors and styles to iOS's
  light-appearance system colors. A `foregroundStyle` applies to the node and its descendants, and
  button labels take the tint color unless they set their own style.
- **Backgrounds** fill the bounds at their position in the modifier chain. Each node records those
  bounds in `modifierFrames`.
- **Symbols** draw as placeholder rings until an open-source icon set replaces SF Symbols.
- **PNG** output uses a small built-in deflate encoder. A screen of mostly flat color compresses
  to about 50 KB at 2× scale.

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
JSON; frames are binary RGBA. Set `PARHELION_DEBUG=1` to trace events and messages in both
processes.

Pointer input follows iOS: a press on a button highlights it, moving off the button cancels the
highlight, and releasing over the same button taps it. `ViewHost.pointerDown(at:)`,
`pointerMoved(to:)`, and `pointerUp(at:)` implement this for every client, not only the window.

### Apps

`App`, `Scene`, and `WindowGroup` mirror SwiftUI so an app's `@main` type compiles. Under
Parhelion, `App.main()` runs a preview session when a window host started the app. Otherwise it
runs headlessly: it resolves the first window and prints the tree, or writes it to a PNG file
with `--png`.

## Planned layers

- **Window.** A window host in `Tools/` shows frames that the app process renders off screen, and
  sends mouse and keyboard input back over a local socket. Only the host depends on SDL3
  ([ADR 0004](adr/0004-pure-swift-renderer.md)).
- **Input.** The preview translates mouse and keyboard input into the touch model that SwiftUI
  apps expect: a click is a tap, a drag is a touch drag, the mouse wheel and trackpad scroll, and
  the keyboard types into the focused field. Hit testing uses the frames from layout.
- **Hot reload.** A `parhelion` command builds the app package, opens it in the preview, and
  rebuilds when a source file changes. State is kept for views whose structural position did not
  change.
- **Agent server.** A process that exposes `ViewHost` over the Model Context Protocol (MCP), so
  agents can read the tree, tap, type, scroll, take screenshots, and advance a deterministic
  clock, either alongside a person in the same preview or without a window.
- **Fidelity checks.** A macOS CI job that renders the same views with Apple's SwiftUI and
  compares the resolved trees and layouts with Parhelion's.
