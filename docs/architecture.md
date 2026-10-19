# Architecture

This document describes how Parhelion turns SwiftUI source code into something you can inspect and
drive on Linux. It covers the parts that exist today and marks the planned parts as planned.

## Goals

1. **Source compatibility.** Code written against SwiftUI compiles against Parhelion without
   changes. The same package builds for iOS with Apple's SDK and for Linux with Parhelion.
2. **Behavioral fidelity.** Where Parhelion implements an API, the API behaves the way SwiftUI
   does, including identity, state lifetime, and update rules.
3. **Programmable by default.** Everything a person can see or do in a Parhelion app is available
   to code as data and function calls: the tree, the state, input, and (planned) time.

Pixel-perfect rendering is not a goal. Parhelion aims to look close enough to judge a layout, and
to behave exactly enough to test against.

## Modules

| Module | Platforms | Role |
| --- | --- | --- |
| `ParhelionUI` | Linux (macOS planned) | The SwiftUI-compatible API and the headless runtime. |
| `SwiftUI` | Linux only | Re-exports `ParhelionUI` so that `import SwiftUI` compiles. See [ADR 0001](adr/0001-swiftui-module-shim.md). |

Planned modules: a renderer, a windowing and input layer, and an agent server. See the
[roadmap](roadmap.md).

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

### Interaction

`ViewHost` delivers input by node identifier. Today it supports taps on buttons
(`tap(_:)` and `tapButton(labeled:)`). Every failure is a typed `InteractionError` that names the
problem, so an agent can recover without parsing messages.

### Apps

`App`, `Scene`, and `WindowGroup` mirror SwiftUI so an app's `@main` type compiles. Under
Parhelion, `App.main()` currently runs headlessly: it resolves the first window and prints the
tree. With a renderer, it will open a window.

## Planned layers

- **Layout.** A layout pass that assigns a frame to every node, following SwiftUI's
  propose-and-respond model: the parent proposes a size, the child chooses its size, and the
  parent places it.
- **Rendering.** A backend that draws the laid-out tree into a phone-sized window. The choice of
  backend is open; see [ADR 0002](adr/0002-defer-renderer-backend.md).
- **Agent server.** A process that exposes `ViewHost` over the Model Context Protocol (MCP), so
  agents can read the tree, tap, type, scroll, take screenshots, and advance a deterministic
  clock.
- **Fidelity checks.** A macOS CI job that renders the same views with Apple's SwiftUI and
  compares the resolved trees and layouts with Parhelion's.
