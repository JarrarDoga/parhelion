# Roadmap

Milestones are ordered. Each one is usable on its own. Dates are not promised.

## 0.1: Headless core (in progress)

- [x] `View`, `ViewBuilder`, structural identity, and the `ViewNode` tree
- [x] `@State` and `@Binding` with SwiftUI's lifetime rules
- [x] Stacks, `Text`, `Image`, `Button`, `Spacer`, `Color`
- [x] `padding`, `foregroundStyle`, and `imageScale`
- [x] `App`, `Scene`, `WindowGroup`, and a headless runner
- [x] `import SwiftUI` source compatibility on Linux
- [x] `@Environment` and the environment values that modifiers read
- [x] `ForEach`
- [x] `Group` and `AnyView`
- [x] `font`, `bold`, `frame`, and `background` modifiers
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
- [x] `TextField` with keyboard input, focus, and a caret
- [x] Keyboard navigation between text fields with Tab and Shift-Tab
- [ ] Text selection, copy, and paste

## 0.5: Agent server

- [x] An MCP server: read the tree, tap, type, scroll, take a screenshot: `parhelion mcp`
- [x] Off-screen rendering, so another app can embed or stream the preview: the socket protocol's
      commands and screenshots
- [x] An agent and a person using the same app: `parhelion mcp --window`
- [ ] A manual clock for agents, so that `wait` advances time instead of sleeping
- [x] Extend the deterministic clock to animations
- [ ] Extend the deterministic clock to timers

## 0.6: More of SwiftUI

- [x] `List` and `Section`
- [x] `NavigationStack` and `NavigationLink`
- [x] `sheet` and `alert`
- [x] Animations

## 0.7: Real apps (in progress)

- [ ] `@Observable`, `@Bindable`, bindings into models and collections, `Group`, `AnyView`, and
      `onAppear`, `onChange`, and `task` ([#26](https://github.com/JarrarDoga/parhelion/issues/26))
- [ ] `Toggle`, `Slider`, `Stepper`, `Picker`, `LabeledContent`, and `Divider` with iOS 27's look
      ([#27](https://github.com/JarrarDoga/parhelion/issues/27))
- [ ] `TabView` with iOS 27's glass tab bar, `Label`, and open-source symbol images in place of SF
      Symbols ([#28](https://github.com/JarrarDoga/parhelion/issues/28))
- [ ] Dark mode, Dynamic Type, the scroll edge effect, asset catalog images, `AsyncImage`, grids,
      and more styling modifiers ([#30](https://github.com/JarrarDoga/parhelion/issues/30))

## 0.8: Agent workflow

- [ ] A manual clock, accessibility identifiers, recorded interaction tests, and snapshot tests
      ([#31](https://github.com/JarrarDoga/parhelion/issues/31))

## 0.9: Preview anywhere (in progress)

- [ ] The preview in a browser, from any device, over a WebSocket
      ([#25](https://github.com/JarrarDoga/parhelion/issues/25))
- [ ] The preview in terminals that support the Kitty graphics protocol

## 0.10: Device loop

- [ ] Build, install, and run the same sources on a real iPhone with xtool
      ([#32](https://github.com/JarrarDoga/parhelion/issues/32))

## 1.0: Release

- [ ] API documentation with DocC
- [ ] Before the repository goes public: private vulnerability reporting, a contact in the code of
      conduct, and no pull requests from forks on the self-hosted runners
- [ ] A stable preview protocol and command-line interface

## Exploring

- Previewing React Native and Expo apps through an out-of-tree platform
  ([#29](https://github.com/JarrarDoga/parhelion/issues/29))

## Continuous: Fidelity

- [x] Device chrome: the status bar, the Dynamic Island, the home indicator, rounded screen
      corners, a phone bezel in the window, and iPhone presets with `--device`
- [x] iOS 27 typography with Inter in four weights, system colors, large navigation titles, and
      inset grouped list metrics
- [x] iOS 27 Liquid Glass: toolbar and back buttons, alerts, sheets, and button styles
- [x] Animation paced to the simulated iPhone's refresh rate, and iPhone 18 Pro presets
- [ ] Faster Liquid Glass, by caching glass between frames, so alerts and sheets hold 120 Hz
- [ ] The scroll edge effect, with content laid out under the navigation bar
- [ ] Letter spacing, to bring Inter's widths closer to San Francisco's
- [ ] CI on macOS and on Linux arm64
- [ ] Verify each constant in `LayoutDefaults.swift` against Apple's SwiftUI
- [x] Symbol images: substitute an open-source icon set for SF Symbols
- [ ] A macOS CI job that resolves the same views with Apple's SwiftUI and compares the trees
- [ ] Layout comparison against Apple's SwiftUI for the supported views
