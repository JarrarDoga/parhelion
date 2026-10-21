# Roadmap

Milestones are ordered. Each one is usable on its own. Dates are not promised.

## 0.1: Headless core (in progress)

- [x] `View`, `ViewBuilder`, structural identity, and the `ViewNode` tree
- [x] `@State` and `@Binding` with SwiftUI's lifetime rules
- [x] Stacks, `Text`, `Image`, `Button`, `Spacer`, `Color`
- [x] `padding`, `foregroundStyle`, and `imageScale`
- [x] `App`, `Scene`, `WindowGroup`, and a headless runner
- [x] `import SwiftUI` source compatibility on Linux
- [ ] `@Environment` and the environment values that modifiers read
- [x] `ForEach`
- [ ] `Group` and `AnyView`
- [ ] `font`, `bold`, `frame`, and `background` modifiers
- [ ] API documentation with DocC

## 0.2: Preview window

- [x] A layout pass that assigns a frame to every node
- [x] Text measurement with a bundled open-source font
- [x] Stack layout, spacing, alignment, `Spacer`, `padding`, and `frame`
- [x] Frames in the `ViewNode` tree and in the JSON output
- [x] Hit testing: tap by screen position
- [ ] Cache `sizeThatFits` results by node, modifier depth, and proposal, so that layout on every
      state change stays fast
- [ ] Cache glyph outlines between frames
- [x] A renderer: pure-Swift rasterization and PNG output (see [ADR 0004](adr/0004-pure-swift-renderer.md))
- [x] `background` with a shape style
- [x] A phone-sized window on Linux: `parhelion preview`
- [x] Mouse input: click to tap, with a pressed state and drag-away cancel

## 0.3: Hot reload

- [x] `parhelion run`, which builds an app package and opens it in the preview window
- [x] Rebuild and reload on save, keeping `Codable` state where the structure allows
- [x] Apps shaped like `xtool new` creates, through a generated runner package

## 0.4: Scrolling and text input

- [x] `ScrollView` with momentum, driven by the mouse wheel, trackpad, or drag
- [x] A deterministic clock for momentum
- [ ] `TextField` with keyboard input, focus, and selection
- [ ] Keyboard navigation between controls

## 0.5: Agent server

- [ ] An MCP server: read the tree, tap, type, scroll, take a screenshot
- [ ] Off-screen rendering, so another app can embed or stream the preview
- [ ] Extend the deterministic clock to animations and timers

## 0.6: More of SwiftUI

- [ ] `List`, `NavigationStack`, `sheet`, and `alert`
- [ ] Animations

## Continuous: Fidelity

- [ ] CI on macOS and on Linux arm64
- [ ] Verify each constant in `LayoutDefaults.swift` against Apple's SwiftUI
- [ ] Symbol images: substitute an open-source icon set for SF Symbols
- [ ] A macOS CI job that resolves the same views with Apple's SwiftUI and compares the trees
- [ ] Layout comparison against Apple's SwiftUI for the supported views
