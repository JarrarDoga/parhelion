# About

Parhelion is an implementation of the SwiftUI API for Linux, designed so that coding agents can
inspect and drive an app's interface. Read [docs/architecture.md](docs/architecture.md) before
changing anything under `Sources/`.

## Development

- `swift build` and `swift test` work from the repository root. Swift 6.3 or later is required.
- `swift run HelloParhelion` prints the resolved tree of the example app. Add `--ids` or `--json`.
- Before you finish, run the same checks as CI:
  - `swift format lint --strict --recursive Package.swift Sources Tests Examples`
  - `swift build --build-tests -Xswiftc -warnings-as-errors`
  - `swift test`

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
- When you open a pull request, fill in the template's AI assistance section truthfully. Unless a
  person has told you they reviewed the change, choose *Generated, not reviewed*.
