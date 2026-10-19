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
> Parhelion is pre-alpha. Today it resolves views, state, and taps without a window. Layout, the
> preview window, and hot reload are the next milestones. See [Status](#status) and the
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

The bundled example is the app that `xtool new` generates, copied without changes:

```console
$ swift run HelloParhelion
Root
└─ VStack padding=all
   ├─ Image foregroundStyle=tint imageScale=large systemName=globe
   └─ Text "Hello, world!"
```

Pass `--json` for the tree as JSON, or `--ids` to show node identifiers.

## Status

| Area | Supported today |
| --- | --- |
| Views | `Text`, `Image`, `Button`, `VStack`, `HStack`, `ZStack`, `Spacer`, `Color`, `EmptyView` |
| Builders | Multiple children, `if`/`else`, optional content |
| State | `@State` and `@Binding`, with SwiftUI's structural identity and lifetime rules |
| Modifiers | `padding`, `foregroundStyle`, `imageScale` (recorded, not yet laid out) |
| App | `App`, `Scene`, `WindowGroup`, with a headless runner |

Not yet available: layout, rendering, text measurement, lists and scrolling, navigation, the
environment, animation, and gestures other than tap. The [roadmap](docs/roadmap.md) lists the
order of work.

## Requirements

- Linux on x86_64. CI tests x86_64 only; arm64 should work but is not tested yet.
- Swift 6.3 or later

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
each one as a `ViewNode`. `@State` storage belongs to the host and is keyed by a view's
structural position, so state survives updates and is discarded when the view leaves the tree.
Taps run the button's action, and the host evaluates the tree again.

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
