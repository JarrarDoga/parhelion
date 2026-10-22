# About

Parhelion is an implementation of the SwiftUI API for Linux, designed so that coding agents can
inspect and drive an app's interface. Read [docs/architecture.md](docs/architecture.md) before
changing anything under `Sources/`.

## Development

- `swift build` and `swift test` work from the repository root. Swift 6.3 or later is required.
- `swift run HelloParhelion` prints the resolved tree of the example app. Add `--frames`, `--ids`,
  or `--json`, or `--png PATH` to draw it. `swift run Counter` is an interactive example.
- `PARHELION_BENCHMARK=1 swift test --filter "renderTiming|canvasTiming|primitiveTiming"` prints layout and render
  timings. Add `-c release -Xswiftc -enable-testing` for optimized numbers.
- To check rendering, write a PNG with `--png` and look at it. Never open windows on the user's
  desktop from a shell; the window host is for the user to run.
- Before you finish, run the same checks as CI:
  - `swift format lint --strict --recursive Package.swift Sources Tests Examples Tools/parhelion-cli/Package.swift Tools/parhelion-cli/Sources Tools/parhelion-cli/Tests Tools/parhelion-cli/Fixtures`
  - `swift build --build-tests -Xswiftc -warnings-as-errors`
  - `swift test`

### The parhelion tool

- Build it with `swift build --package-path Tools/parhelion-cli`. It needs SDL3 (`SDL3-devel` on
  Fedora, `libsdl3-dev` on Ubuntu 25.04 or later).
- Check it without a display:
  `SDL_VIDEODRIVER=offscreen Tools/parhelion-cli/.build/debug/parhelion preview --exit-after-first-frame .build/debug/Counter`.
- Set `PARHELION_DEBUG=1` to trace events and messages in the host and the app.
- `swift test --package-path Tools/parhelion-cli` tests package inspection, runner generation,
  file watching, and the MCP server in `ParhelionTooling`.
- `parhelion run --exit-after-first-frame --package-path Tools/parhelion-cli/Fixtures/LibraryApp`
  checks an `xtool`-shaped app end to end.
- `SDL_VIDEODRIVER=offscreen Scripts/mcp-session.py Tools/parhelion-cli/.build/debug/parhelion`
  drives `parhelion mcp` the way an agent does and checks each answer, including a failed build
  and state across a rebuild.
- Never open a preview window on the user's desktop. Exporting `DISPLAY` is not enough: SDL3
  prefers Wayland when `WAYLAND_DISPLAY` is set. Use `SDL_VIDEODRIVER=offscreen`, or an isolated
  display with `WAYLAND_DISPLAY` unset and `SDL_VIDEODRIVER=x11`.

## Conventions

- Public API on views must match SwiftUI's names, signatures, and behavior. Put Parhelion-only API
  on `ViewHost` and `ViewNode`.
- Never copy code, headers, or assets from Apple's SDKs.
- Primitive views have `Body == Never` and conform to the internal `PrimitiveView` protocol.
  Their node `kind` is the SwiftUI type name.
- Every new view or modifier needs a test that checks the resolved tree with `outline()`.
- If you change the output of the README example, update `README.md` and
  `Tests/ParhelionUITests/ReadmeExampleTests.swift` together.
- Record user-visible changes under `Unreleased` in `CHANGELOG.md`.
- Record design decisions that are hard to reverse as a new file in `docs/adr/`.
- If you change `Package.swift`, run `Scripts/check-ios-build.sh` before opening a pull request.
  It needs xtool with the iOS SDK, so CI cannot run it.
- Never add SwiftPM `resources:` to a target. They break iOS builds of apps that depend on
  Parhelion; see `docs/adr/0003-no-swiftpm-resources.md`.
- `Sources/ParhelionRender/Inter*FontData.swift` are generated. To change a font, replace it in
  `Fonts/` and run, for example,
  `Scripts/embed-font.sh Fonts/Inter-Regular.ttf > Sources/ParhelionRender/InterRegularFontData.swift`.
- When you open a pull request, fill in the template's AI assistance section truthfully. Unless a
  person has told you they reviewed the change, choose *Generated, not reviewed*.
