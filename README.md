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
> in a preview window that reloads when you save, where you tap, scroll, and type with your mouse
> and keyboard. Coding agents drive the same apps through an MCP server. See [Status](#status)
> and the [roadmap](docs/roadmap.md).

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
  the app.
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
  <img src="docs/images/counter.png" alt="The Counter example rendered by Parhelion under an iOS status bar: a count label, a gray bordered Decrease button and a blue prominent Increase button, a Reset button, and the home indicator." width="240">
</p>

The `Tasks` example shows the rest of the iOS 27 interface: a large title and a list, a pushed
screen with a glass back button, an alert, and a sheet with glass toolbar buttons. Its images come
from `ViewHost`, which taps through the app, and `swift test` compares them with fresh renders
(see [Snapshot tests](docs/architecture.md#snapshot-tests)):

<p align="center">
  <img src="docs/images/tasks-list.png" alt="The Tasks list: a large Tasks title, an Add button on a glass capsule, and To do and Done sections." width="190">
  <img src="docs/images/tasks-detail.png" alt="The Buy milk screen: a chevron back button on a glass circle above a large title." width="190">
  <img src="docs/images/tasks-alert.png" alt="A Delete this task? alert on large glass with gray Cancel and red Delete capsule buttons over a dimmed screen." width="190">
  <img src="docs/images/tasks-sheet.png" alt="The New task sheet: Cancel on a glass capsule and a blue Add button above a title field." width="190">
</p>

The `Tabs` example shows iOS 27's floating glass tab bar, with three tabs and a search tab that
each keep their own navigation stack, and symbol images drawn with
[Phosphor Icons](https://phosphoricons.com). Its images are checked the same
way:

<p align="center">
  <img src="docs/images/tabs-places.png" alt="The Places tab: a list of places, each with a Phosphor symbol, scrolling under a glass tab bar with Places selected and a separate search circle." width="190">
  <img src="docs/images/tabs-place.png" alt="The Café screen pushed in the Places tab: a large blue cup symbol, a visit count, and a Visit button above the tab bar." width="190">
  <img src="docs/images/tabs-settings.png" alt="The Settings tab: grouped rows labeled with bell, lock, sun, and person symbols, with Settings selected in the tab bar." width="190">
  <img src="docs/images/tabs-search.png" alt="The search tab: a search field and matching places, with the search circle highlighted." width="190">
</p>

The same screens draw in the dark appearance, with iOS 27's dark system colors and dark Liquid
Glass. The Settings example's Appearance picker sets `preferredColorScheme(_:)`, which turns the
whole window dark on a light device. Text styles follow the Dynamic Type size: rows, titles, and
footers grow with their text, while the toolbar, the tab bar, and segmented controls keep their
size. These images come from
`PARHELION_README_IMAGES=docs/images swift test --filter writeAppearanceReadmeImages`:

<p align="center">
  <img src="docs/images/tasks-list-dark.png" alt="The Tasks list in dark: black screen, 28-gray grouped cells, white text, and an Add button on dark glass." width="190">
  <img src="docs/images/tasks-alert-dark.png" alt="A Delete this task? alert on dark large glass with dark gray Cancel and red Delete capsules over a dimmed screen." width="190">
  <img src="docs/images/tasks-sheet-dark.png" alt="The New task sheet in dark: a 28-gray sheet with a lighter title field, Cancel on dark glass, and a blue Add button." width="190">
  <img src="docs/images/tabs-places-dark.png" alt="The Places tab in dark, scrolling under a dark glass tab bar with Places selected in blue." width="190">
</p>

<p align="center">
  <img src="docs/images/settings-dark.png" alt="The Settings example with Appearance set to Dark: switches, a slider, and a segmented control in dark grouped cells." width="190">
  <img src="docs/images/settings-menu-dark.png" alt="The Appearance menu open on dark glass, with Dark checked." width="190">
  <img src="docs/images/tasks-list-accessibility2.png" alt="The Tasks list at the accessibility2 text size: a larger title, taller rows, and a footer on two lines, with the Add button at its usual size." width="190">
  <img src="docs/images/settings-xxxlarge.png" alt="The Settings example at the xxxLarge text size, with larger labels in taller rows and the segmented control at its usual size." width="190">
</p>

A `ScrollView` or `List` that is a navigation stack's screen, or a tab's content, takes the whole
screen and scrolls under the navigation bar and the tab bar. While content lies under a bar, the
scroll edge effect blurs it: the soft style fades a heavy blur out toward the content, and the hard
style covers it with a nearly opaque blur and a dividing line. `scrollEdgeEffectStyle(_:for:)` and
`scrollEdgeEffectHidden(_:for:)` choose, and `contentMargins` and `safeAreaPadding` inset the
content. These images come from
`PARHELION_README_IMAGES=docs/images swift test --filter "ScrollEdgeTests/writeReadmeImages"`:

<p align="center">
  <img src="docs/images/scroll-edge-soft.png" alt="A list scrolled under an inline navigation bar and a glass tab bar, with the soft scroll edge effect: the rows at the top and bottom are blurred and faded." width="190">
  <img src="docs/images/scroll-edge-soft-dark.png" alt="The same list in dark, with the soft scroll edge effect." width="190">
  <img src="docs/images/scroll-edge-hard.png" alt="A list scrolled under an inline navigation bar with the hard scroll edge effect: a nearly opaque white blur above a hairline." width="190">
  <img src="docs/images/scroll-edge-hard-dark.png" alt="The same list in dark, with the hard scroll edge effect: a darkened blur above a hairline." width="190">
</p>

Shapes, gradients, and the styling modifiers draw as in SwiftUI: `clipShape`, `overlay`,
`shadow`, and `scaleEffect` apply at their place in the modifier chain without changing layout.
`Image` reads an app's `Assets.xcassets` from its target's resource bundle, with 1×, 2×, and 3×
files and dark appearances, and Parhelion decodes the PNG files itself. `AsyncImage` loads in a
`task`, so tests and agents can wait for it. `LazyVGrid`, `LazyHGrid`, and `Grid` lay out their
cells. These images come from
`PARHELION_README_IMAGES=docs/images swift test --filter writeContentReadmeImages`:

<p align="center">
  <img src="docs/images/content-shapes.png" alt="Shapes: a rectangle, rounded rectangle, circle, capsule, and ellipse; a pink-to-indigo gradient card with a shadow and white overlay text; a circle-clipped gradient with a green badge, a three-slice pie drawn by a custom shape, a gradient star scaled up, mirrored text, and a teal bar clipped to rounded corners." width="190">
  <img src="docs/images/content-images.png" alt="Images: a landscape from an asset catalog filling a rounded frame, the same image scaled to fit, an orange template star, a green speech bubble stretched by its cap insets, an AsyncImage clipped to a circle, the gray placeholder of an AsyncImage that failed, and the ring of a missing image." width="190">
  <img src="docs/images/content-images-dark.png" alt="The Images screen in dark: the asset catalog's dark landscape at night, white text, and the darker placeholder." width="190">
  <img src="docs/images/content-grids.png" alt="Grids: twelve numbered color tiles in an adaptive lazy grid, a Grid of plans with a trailing-aligned price column and a row spanning two columns, and capsule chips in a two-row lazy horizontal grid." width="190">
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
└─ VStack padding(16)  [147.63, 412.54, 97.75 × 51.93]
   ├─ Image foregroundStyle=tint imageScale=large systemName=globe  [185.54, 412.54, 21.93 × 21.93]
   └─ Text "Hello, world!"  [147.63, 442.47, 97.75 × 22]
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
Building MyApp: debug build of the app, with Parhelion optimized...
Running MyApp. Save a file to reload. Close the window to quit.
Change detected. Rebuilding...
Reloaded in 1.44 s: build 1.42 s, restart 0.02 s.
```

`parhelion run` builds the app, opens it, and watches the package's Swift files. When you save,
it rebuilds in the background and restarts the app in the same window. `@State` values whose type
is `Codable` keep their values across the reload. If the build fails, the errors appear in the
terminal with paths to your own files, and the last working version keeps running.

It runs a package's executable product, or, for apps created with `xtool new`, the library's
`@main` type, through a small generated runner package. To open an already-built executable
without watching, use `parhelion preview .build/debug/Counter`.

An app that needs something built before Swift, such as a Rust library with UniFFI bindings, says
how in `parhelion.json` next to its `Package.swift`:

```json
{
  "preBuild": "scripts/build-ios.sh --linux",
  "watch": ["../crates", "../Cargo.toml"],
  "libraryPaths": ["../target/debug"]
}
```

`preBuild` is a shell command that runs in the package before every `swift build`; it finds the
build configuration in `PARHELION_CONFIGURATION`. Its errors appear like Swift errors, in the
terminal, on the web page, and in `parhelion mcp`. `watch` lists more files and directories
whose changes rebuild the app, such as the Rust crates (a Cargo `target` directory is skipped).
`libraryPaths` lists directories with prebuilt `.a` and `.so` files: the linker searches them for
the libraries that a target links with `.linkedLibrary`, and the app finds a `.so` there when it
starts. `--pre-build`, `--watch`, and `--library-path` do the same on the command line. Paths
are relative to the package. Have the command write generated files only when they changed,
because a write to a Swift file counts as an edit. The `RustApp` fixture in
`Tools/parhelion-cli/Fixtures` shows the whole setup.

The window shows the screen inside a phone, like the iOS Simulator, with the status bar, the
Dynamic Island, and the home indicator. `--device` picks the iPhone to simulate: iPhone 16 (the
default), 16 Plus, 16 Pro, 16 Pro Max, 16e, 17, 17 Pro, 17 Pro Max, Air, 18 Pro, or 18 Pro Max,
as in `parhelion run --device "iPhone 18 Pro Max"`. `--no-bezel` shows the screen without the
phone around it. `--zoom` changes the window size, and `--scale` changes the pixels per point the
app renders at. `--overlay board.png` draws a design board PNG over the screen, at
`--overlay-opacity` (0 to 1, default 0.5), to compare by eye.

Animation in the window follows the display: the window waits for each refresh, at 60, 180, or
240 Hz, and the app draws each frame for the moment it will be on screen. Animation never runs
faster than the iPhone it simulates: 120 frames per second on models with ProMotion, which is
every other refresh on a 240 Hz display, and 60 on iPhone 16, 16 Plus, and 16e. By default
`parhelion run` builds your app without optimization, so a one-line edit rebuilds in about a
second, and Parhelion with optimization, so frames render as fast as in a release build. If your
package pins Parhelion to a version, SwiftPM does not allow that split, and `parhelion run`
optimizes the whole build instead; it says so when it starts. `parhelion run -c release` builds
everything optimized. Builds go to `.build/parhelion`, so they do not disturb your own
`swift build`.

Press Control-Shift-A to switch the simulated iPhone between light and dark, and Control-Alt-Plus
or Control-Alt-Minus to make its text larger or smaller, as the Simulator's Toggle Appearance and
text size commands do. The window's title shows the setting, and the app keeps it when it
reloads. To start with one, set `PARHELION_COLOR_SCHEME=dark` or
`PARHELION_DYNAMIC_TYPE_SIZE=accessibility2`; an app run with `--png` reads them too.

The app draws its own frames and sends them to the window over a local socket, so the same app
can also run with no window at all, for tests and agents.

### In a browser

`--web` shows the preview on a web page instead of in a window. Use it from another device, such
as your Mac or iPhone over Tailscale, or on a machine with no display:

```console
$ parhelion run --web --package-path ~/Code/MyApp
Open the preview in a browser:
  http://127.0.0.1:8417/?token=3f9c0b7e2a6d4c1f8e5b9a0d7c3e6f21
Building MyApp: debug build of the app, with Parhelion optimized...
Running MyApp. Save a file to reload. Press Control-C to quit.
```

The page shows the phone scaled to fit the browser window. Click or touch to tap, drag to scroll,
scroll with the mouse wheel or trackpad, and type; on a phone, the Keyboard button opens the
keyboard. The Light or Dark button and the text size menu above the phone switch the appearance
and the Dynamic Type size, for the window and every page at once. The page stays connected while `parhelion run` rebuilds and restarts the app, and shows
build errors. It needs a browser from 2023 or later: Chrome 80, Safari 16.4, or Firefox 113.

Anyone who can open the page controls the app, so the URL carries a random token, and the tool
refuses every request without it. The tool listens on 127.0.0.1 unless you choose another
address with `--web-address`: a Tailscale address such as `100.101.102.103`, or `0.0.0.0` for
every address. `--web-port` chooses the port; by default the tool uses 8417, or the next free
port after it. `parhelion preview --web` works the same way. `parhelion mcp --web` prints the URL
to standard error and gives it to the agent, and with `--window` too, the window and the page
show the same app.

The tool sends the page only the rows of each frame that changed, compressed. Scrolling a full
screen costs about 35 to 40 KB a frame, so the page keeps up with a 60 Hz iPhone over a 50 Mbit/s
connection.

## Recorded tests

Record a run through your screens once, and replay it without a window in CI:

```console
$ parhelion run --record flows/checkout.json --package-path ~/Code/MyApp
$ parhelion test flows/checkout.json --package-path ~/Code/MyApp
PASS flows/checkout.json (14 steps)
1 flow passed.
```

While you use the window, the app writes your taps, drags, scrolls, typing, and pauses to a JSON
file. A tap names the control by its accessibility identifier if only it has that identifier,
else by its label if only it has that label, so a flow survives layout changes. The flow starts
with a checkpoint of the screen, adds one whenever you press F2, and ends with one when you close
the window. A reload ends the recording.

`parhelion test` starts the app once for each flow, headless and on the manual clock, so waits and
`Task.sleep` take no real time. At each checkpoint it compares the tree's outline, without frames,
with the recorded one, prints the lines that differ, and exits nonzero on a mismatch. After an
intended change, `parhelion test --update` rewrites the checkpoints. A flow is a list of steps,
so you can edit one by hand or have an agent write it:

```json
{ "command": { "tapAccessibilityIdentifier": { "_0": "checkout" } } }
{ "wait": 0.5 }
{ "expect": ["Root", "└─ Text \"Total: $12\""] }
```

From a Swift Testing test, `ViewHost.replay(_:)` plays a `Flow` against a `ViewHost`; there a
`Task.sleep` in the app still takes real time.

## Your own SF Symbols

Parhelion draws `Image(systemName:)` with Phosphor Icons, because Apple's license does not let
Parhelion ship SF Symbols. If you have the SF Symbols app, Parhelion can draw your copy instead,
in the font's weight. It contains none, and downloads none.

In the SF Symbols app, select the symbols you use (or all of them), choose File > Export Symbol,
save them as SVG into a folder, and import the folder:

```sh
parhelion symbols import ~/Documents/symbols
parhelion symbols status
```

That copies only the outlines Parhelion draws, to `~/.local/share/parhelion/symbols`, never into a
repository or a build. Instead of importing, set `PARHELION_SF_SYMBOLS` to the folder of exports.
A name your copy lacks falls back to Phosphor, then to a ring. In the view tree and in
`parhelion mcp`, a symbol drawn from your copy has `symbolSource=sfSymbols`.

**The license is yours to check.** Apple allows SF Symbols only for designing and developing apps
for Apple platforms, and forbids redistributing them. Whether using your copy on Linux to preview
an iOS app is within that license is your responsibility; Parhelion does not claim it is
permitted. Never commit exports: CI fails if SF Symbols data appears in the repository.

## Agents

`parhelion mcp` serves your app to a coding agent over the Model Context Protocol. Register it
with Claude Code from your app's directory:

```console
$ claude mcp add parhelion -- parhelion mcp --package-path .
```

The agent gets these tools:

| Tool | What it does |
| --- | --- |
| `get_view_tree` | The screen as a tree of views with identifiers and frames, as an outline or JSON |
| `screenshot` | A PNG of the screen, with the status bar and the home indicator |
| `tap`, `type_text`, `press_key` | Tap by identifier, label, or position; type into text fields; Tab, Return, Backspace, and the caret keys, with Up and Down in vertical text fields |
| `long_press` | Hold a press at a point for a duration, so a view's long press gesture fires |
| `scroll`, `scroll_to`, `drag`, `wait` | Scroll like a mouse wheel, to an offset, or by dragging with momentum, and wait for it to settle |
| `audio_interruption`, `audio_route_change` | Post `AVAudioSession`'s interruption (began, ended, with the resume option) and route change (headphones unplugged) notifications, so an app's audio handlers run |
| `set_appearance` | Switch the simulated iPhone between light and dark, and set its Dynamic Type size; the setting stays for later rebuilds |
| `set_scene_phase` | Move the app between `active`, `inactive`, and `background`, so `onChange(of: scenePhase)` actions run; the window does the same when it loses focus or is minimized |
| `compare_image` | Render the screen at a design board PNG's scale and return the share of pixels that differ, within a tolerance, with a diff PNG that marks them in red |
| `rebuild`, `app_output` | Rebuild after editing the code, keeping `@State`, with compiler errors on failure; read what the app printed |

Each interaction reports the screen's revision, so the agent can tell whether it changed
anything. Add `--window` to watch the app in a preview window and use it yourself while the agent
works, or `--web` to do that from a browser.

### Many sessions on one machine

Sessions share nothing, so `parhelion mcp` processes can run side by side, each in
its own package directory, such as one git worktree per agent. Each session builds into its own
`.build/parhelion`, listens on a Unix socket named after its process ID in the temporary
directory, writes one state file there, and draws frames into anonymous shared memory. The SDL
`offscreen` driver keeps no state outside the process. Two things can collide: sessions in the
same package directory, which share one `.build/parhelion` (not tested), and `--web`, which tries only
the 11 ports from 8417, so give each session `--web-port 0`.

Memory goes to the build, not to the session. Measured on 2026-11-06 with a scaffold of eight tabs
and a fixture model of 1,535 songs, on a 6-core machine that other builds were using, as the
proportional set size of every process under `parhelion mcp`:

| | Peak | When idle |
| --- | --- | --- |
| The first build in a fresh directory, default jobs | 820 MB | |
| The first build, `--jobs 2`, 10 sessions at once | 350 to 480 MB each, 4.0 GB together | |
| The app | 13 MB | 13 MB |
| The host (`parhelion mcp`) | 6 to 12 MB | 6 to 12 MB |
| A session after its build | | 18 to 25 MB |

Ten sessions in ten directories, started in the same second with `--jobs 2`, all built and
answered `get_view_tree` without errors. The machine's available memory fell by 3.5 GB at the
lowest point, and each build took about 9 minutes because the CPUs were shared by all of them.
Later builds, after an edit, are incremental and take a few seconds.

So the limit is how many first builds run in the same minute, not how many sessions are open.
Plan for 0.5 GB per session that is building and 20 MB per idle one: 25 sessions need about
0.5 GB when idle, and a start of 10 at once peaks near 4 GB. Cap the builds with `--jobs N` or
the `PARHELION_BUILD_JOBS` environment variable, the way Cargo's `CARGO_BUILD_JOBS` works, and
use `--jobs 2` to `--jobs 4` when something else, such as Cargo, uses the same cores. The option
wins over the variable. `Scripts/measure-mcp-sessions.py` repeats the measurement:

```console
$ SDL_VIDEODRIVER=offscreen Scripts/measure-mcp-sessions.py \
    Tools/parhelion-cli/.build/debug/parhelion --sessions 10 --jobs 2
```

## Status

| Area | Supported today |
| --- | --- |
| Views | `Text`, `Image` (symbols and asset catalogs), `AsyncImage`, `Label`, `Button`, `TextField`, `VStack`, `HStack`, `ZStack`, `Spacer`, `Color`, `LinearGradient`, `Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, `Capsule`, `Path`, and custom shapes, `LazyVGrid`, `LazyHGrid`, `Grid`, `ScrollView`, `List`, `Section`, `ForEach`, `NavigationStack`, `NavigationLink`, `TabView` and `Tab`, `EmptyView`; sheets, full-screen covers, and alerts |
| Builders | Multiple children, `if`/`else`, optional content |
| State | `@State` and `@Binding`, with SwiftUI's structural identity and lifetime rules; `@Environment` with `dismiss`, `isPresented`, `colorScheme`, `dynamicTypeSize`, and custom keys; `@ScaledMetric` |
| Modifiers | `padding`, `frame` (fixed and flexible), `background`, `foregroundStyle`, `font`, `fontWeight`, `bold`, `preferredColorScheme`, `dynamicTypeSize` (a size or a range), `imageScale`, `labelStyle`, `tabItem`, `listStyle`, `navigationTitle`, `navigationBarTitleDisplayMode`, `navigationDestination`, `toolbar`, `opacity`, `offset`, `overlay`, `clipShape`, `clipped`, `cornerRadius`, `shadow`, `scaleEffect`, `aspectRatio`, `scaledToFit`, `scaledToFill`, `fill`, `resizable`, `renderingMode`, the grid cell modifiers, `animation`, `transition`, and `Color.opacity` |
| Animation | `withAnimation` and `animation(_:value:)` with timing curves and springs on a deterministic clock; opacity, move, slide, offset, and push transitions; animated navigation and presentations |
| Layout | SwiftUI's propose-and-respond stack algorithm, iOS text styles at every Dynamic Type size and `Font.custom`, text wrapping with the bundled Inter font in four weights, large and inline navigation titles, the screens and safe areas of nine iPhones from iPhone 16 to iPhone 17 Pro Max |
| Input | Tap by node, by button label, or by screen position; press, drag away to cancel, and release with the mouse; scroll by dragging with momentum, or with the mouse wheel and trackpad; type into text fields, with the caret keys, Backspace, Delete, and Tab between fields |
| Window | `parhelion run` with hot reload that keeps `Codable` state, and `parhelion preview`; an SDL3 window host for Wayland and X11 that shows the screen in a phone bezel; `--web` for the same preview in a browser |
| Agents | `parhelion mcp`, with or without a window or web page |
| Rendering | Anti-aliased shapes, gradients, clips, shadows, and Inter text drawn in pure Swift at any scale, with PNG output and PNG decoding; iOS 27's system colors and inset grouped lists, in light and dark; the status bar, Dynamic Island or notch, home indicator, and rounded screen corners; the floating glass tab bar; SF Symbol names drawn with Phosphor Icons, and other names as placeholder rings |
| App | `App`, `Scene`, `WindowGroup`, with a headless runner |

Not yet available: iOS 27's Liquid Glass toolbar buttons, alerts,
and sheets, button styles, most built-in environment values, rotation effects, strokes, JPEG, PDF, and HEIF images, repeating animations, animation, and gestures other than tap. Layout constants that Parhelion assumes about
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
