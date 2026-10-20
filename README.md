# Parhelion

[![CI](https://github.com/JarrarDoga/parhelion/actions/workflows/ci.yml/badge.svg)](https://github.com/JarrarDoga/parhelion/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

SwiftUI for Linux, built for coding agents.

Parhelion is an open-source implementation of the SwiftUI API that runs natively on Linux. Your
app's source, `import SwiftUI` included, compiles against Parhelion without changes. Parhelion runs
it in a live preview window that reloads when you save, and you use the app with your mouse and
keyboard. The same runtime exposes the view tree, the state, and the input as a programming
interface, so a coding agent can check what is on screen and what happens when it taps, instead
of guessing from a screenshot.

> [!NOTE]
> Parhelion is pre-alpha. Today it resolves, lays out, and draws views, keeps state, and runs apps
> in a preview window that reloads when you save, where you click to tap and scroll with the
> mouse. Keyboard input and an agent server are the next milestones. See [Status](#status) and the
> [roadmap](docs/roadmap.md).

## Why Parhelion

You can already build, sign, and install a real iOS app from Linux with
[xtool](https://github.com/xtool-org/xtool). What is missing is the inner loop: seeing a change
and checking that it works, without a phone or a Mac at hand. Agents need more than a picture of
the screen. They need to know what each element is, which elements accept input, and what
changed after an action.

- **One codebase.** On Linux, `import SwiftUI` resolves to Parhelion. On iOS, it resolves to Apple's
  framework. The same package builds for both.
- **A live preview.** Your app runs in a phone-sized window on your Linux desktop. Click to tap,
  scroll with the mouse wheel or by dragging, and type with the keyboard. Saving a file reloads
  the app. *(Planned: see the roadmap.)*
- **Made for agents.** The resolved view tree is plain `Codable` data with stable structural
  identifiers. The preview window, unit tests, and agents all drive the app through the same
  `ViewHost` API, with or without a window.

## Example

```swift
import SwiftUI

struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
    }
}
```

Host the view, drive it, and read the result:

```swift
let host = ViewHost(Counter())
try host.tapButton(labeled: "Increment")
print(host.root.outline(includeIDs: true))
```

```text
Root
└─ VStack  #Counter/VStack
   ├─ Text "Count: 1"  #Counter/VStack/0/Text
   └─ Button  #Counter/VStack/1/Button
      └─ Text "Increment"  #Counter/VStack/1/Button/Text
```

Parhelion draws the screen itself. This image of the `Counter` example came from
`swift run Counter --png docs/images/counter.png`:

<p align="center">
  <img src="docs/images/counter.png" alt="The Counter example rendered by Parhelion: a count label, red Decrease and blue Increase buttons, and a Reset button." width="240">
</p>

The bundled `HelloParhelion` example is the app that `xtool new` generates, copied without changes:

```console
$ swift run HelloParhelion
Root
└─ VStack padding(16)
   ├─ Image foregroundStyle=tint imageScale=large systemName=globe
   └─ Text "Hello, world!"
```

Pass `--png PATH` to draw the screen to an image, `--frames` to show each node's frame in points,
`--ids` to show node identifiers, or `--json` for the tree as JSON:

```console
$ swift run HelloParhelion --frames
Root  [0, 0, 393 × 852]
└─ VStack padding(16)  [146.21, 413.25, 100.57 × 50.5]
   ├─ Image foregroundStyle=tint imageScale=large systemName=globe  [185.54, 413.25, 21.93 × 21.93]
   └─ Text "Hello, world!"  [146.21, 443.18, 100.57 × 20.57]
```

## Preview window

The `parhelion` tool runs a built app in a window on your Linux desktop. You click to tap, and a
button dims while you hold it, as on iOS. The tool needs SDL3:

```console
$ sudo dnf install SDL3-devel          # Fedora
$ sudo apt install libsdl3-dev         # Ubuntu 25.04 or later
$ swift build -c release --package-path Tools/parhelion-cli
$ cp Tools/parhelion-cli/.build/release/parhelion ~/.local/bin/
```

Then run your app's package:

```console
$ parhelion run --package-path ~/Code/MyApp
Building MyApp...
Running MyApp. Save a file to reload. Close the window to quit.
Change detected. Rebuilding...
Reloaded in 1.6 s.
```

`parhelion run` builds the app, opens it, and watches the package's Swift files. When you save,
it rebuilds in the background and restarts the app in the same window. `@State` values whose type
is `Codable` keep their values across the reload. If the build fails, the errors appear in the
terminal with paths to your own files, and the last working version keeps running.

It runs a package's executable product, or, for apps created with `xtool new`, the library's
`@main` type, through a small generated runner package. To open an already-built executable
without watching, use `parhelion preview .build/debug/Counter`.

`--zoom` changes the window size, and `--scale` changes the pixels per point the app renders at.
`parhelion run -c release` builds with optimizations, which makes scrolling animate at 60 frames
per second at the cost of slower rebuilds.

The app draws its own frames and sends them to the window over a local socket, so the same app
can also run with no window at all, for tests and agents.

## Status

| Area | Supported today |
| --- | --- |
| Views | `Text`, `Image`, `Button`, `VStack`, `HStack`, `ZStack`, `Spacer`, `Color`, `ScrollView`, `ForEach`, `EmptyView` |
| Builders | Multiple children, `if`/`else`, optional content |
| State | `@State` and `@Binding`, with SwiftUI's structural identity and lifetime rules |
| Modifiers | `padding`, `frame` (fixed and flexible), `background`, `foregroundStyle`, `imageScale` |
| Layout | SwiftUI's propose-and-respond stack algorithm, text wrapping with the bundled Inter font, iPhone 16 screen and safe area |
| Input | Tap by node, by button label, or by screen position; press, drag away to cancel, and release with the mouse; scroll by dragging with momentum, or with the mouse wheel and trackpad |
| Window | `parhelion run` with hot reload that keeps `Codable` state, and `parhelion preview`; an SDL3 window host for Wayland and X11 |
| Rendering | Anti-aliased shapes and Inter text drawn in pure Swift at any scale, with PNG output; SF Symbols draw as placeholder rings |
| App | `App`, `Scene`, `WindowGroup`, with a headless runner |

Not yet available: keyboard input and text fields, fonts other than body text, lists and scrolling, navigation, the
environment, animation, and gestures other than tap. Layout constants that Parhelion assumes about
SwiftUI, such as the default padding, are listed in `LayoutDefaults.swift` until a macOS CI job
verifies them. The [roadmap](docs/roadmap.md) lists the
order of work.

## Requirements

- Linux on x86_64. CI tests x86_64 only; arm64 should work but is not tested yet.
- Swift 6.3 or later
- SDL3, only for the `parhelion` preview window

The `SwiftUI` module exists only on Linux, so it never shadows Apple's framework.

## Installation

Add Parhelion to your app's `Package.swift`, and depend on its `SwiftUI` product on Linux only:

```swift
dependencies: [
    .package(url: "https://github.com/JarrarDoga/parhelion.git", branch: "main")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "SwiftUI", package: "parhelion", condition: .when(platforms: [.linux]))
        ]
    )
]
```

When you build for iOS, for example with `xtool dev`, the condition excludes Parhelion and the app
links Apple's SwiftUI. When you build on Linux, the same sources compile against Parhelion.

Parhelion has no tagged release yet. Pin a version once `0.1.0` is out.

## How it works

`ViewHost` evaluates a view's `body` recursively until it reaches primitive views, and records
each one as a `ViewNode`. A layout pass then assigns every node a frame, using SwiftUI's model:
the parent proposes a size, the child picks its size, and the parent places it. `@State` storage
belongs to the host and is keyed by a view's structural position, so state survives updates and
is discarded when the view leaves the tree. Taps run the button's action, and the host evaluates
and lays out the tree again.

`ViewHost.render(scale:)` then draws the tree into pixels with Parhelion's own rasterizer, which
needs no GPU and no system libraries, so screenshots look the same on every machine.

The [architecture overview](docs/architecture.md) covers the design. The
[decision records](docs/adr/) explain the choices behind it.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and
the pull request process. Everyone who takes part must follow the
[Code of Conduct](CODE_OF_CONDUCT.md). To report a security issue, follow
[SECURITY.md](SECURITY.md).

## The name

A parhelion, or sun dog, is a bright image of the sun that appears beside it. Parhelion shows an
image of your iOS app beside the real one.

## License

Parhelion is available under the [Apache License 2.0](LICENSE).

Parhelion is an independent project. It is not affiliated with, sponsored by, or endorsed by
Apple Inc. Apple, iOS, SwiftUI, and Xcode are trademarks of Apple Inc. Parhelion contains no Apple
source code.
