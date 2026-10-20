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

[Unreleased]: https://github.com/JarrarDoga/parhelion/commits/main
