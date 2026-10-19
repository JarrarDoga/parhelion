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
- [ ] `ForEach`, `Group`, and `AnyView`
- [ ] `font`, `bold`, `frame`, and `background` modifiers
- [ ] API documentation with DocC

## 0.2: Layout

- [ ] A layout pass that assigns a frame to every node
- [ ] Text measurement with a bundled open-source font
- [ ] Stack layout, spacing, alignment, `Spacer`, `padding`, and `frame`
- [ ] Frames in the `ViewNode` tree and in the JSON output

## 0.3: Window and input

- [ ] A phone-sized window on Linux
- [ ] A renderer backend (see [ADR 0002](adr/0002-defer-renderer-backend.md))
- [ ] Tap by pointer position, and hit testing
- [ ] `ScrollView` with momentum scrolling
- [ ] `TextField` with keyboard input

## 0.4: Agent server

- [ ] A `parhelion` command-line tool that hosts an app
- [ ] An MCP server: read the tree, tap, type, scroll, take a screenshot
- [ ] A deterministic clock for animations and timers

## 0.5: Fast iteration

- [ ] Rebuild and reload on save, keeping state where the structure allows
- [ ] `List`, `NavigationStack`, `sheet`, and `alert`

## Continuous: Fidelity

- [ ] CI on macOS and on Linux arm64
- [ ] A macOS CI job that resolves the same views with Apple's SwiftUI and compares the trees
- [ ] Layout comparison against Apple's SwiftUI for the supported views
