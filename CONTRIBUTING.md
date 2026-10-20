# Contributing to Parhelion

Thank you for your interest in Parhelion. This guide explains how to report problems, propose
changes, and get a pull request merged.

## Ways to contribute

- **Report a bug.** Open a [bug report](https://github.com/JarrarDoga/parhelion/issues/new/choose).
  Include the smallest view that reproduces the problem and the output of
  `host.root.outline(includeIDs: true)`.
- **Request a SwiftUI API.** Use the *Missing SwiftUI API* issue form. Link the Apple
  documentation page and show the code you want to compile.
- **Send a pull request.** For anything larger than a small fix, open an issue first so we can
  agree on the approach before you write the code.

## Development setup

You need Linux and Swift 6.3 or later. [swiftly](https://www.swift.org/install/linux/)
is the simplest way to install a toolchain.

```console
$ git clone https://github.com/JarrarDoga/parhelion.git
$ cd parhelion
$ swift build
$ swift test
$ swift run HelloParhelion
```

To work on the preview window, install SDL3 (`SDL3-devel` on Fedora, `libsdl3-dev` on Ubuntu 25.04
or later) and build the tool with `swift build --package-path Tools/parhelion-cli`.

The `SwiftUI` shim module, the source compatibility tests, and the examples exist only on Linux.
`ParhelionUI` is intended to build on macOS as well, but CI does not test macOS yet.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests. Every new API needs a test that compiles it the way an app
   would and checks the resolved tree.
3. Format and lint:

   ```console
   $ swift format --in-place --recursive Package.swift Sources Tests Examples \
       Tools/parhelion-cli/Package.swift Tools/parhelion-cli/Sources
   $ swift format lint --strict --recursive Package.swift Sources Tests Examples \
       Tools/parhelion-cli/Package.swift Tools/parhelion-cli/Sources
   ```

4. Build with warnings treated as errors, the way CI does:

   ```console
   $ swift build --build-tests -Xswiftc -warnings-as-errors
   $ swift test
   ```

5. Add an entry under `Unreleased` in [CHANGELOG.md](CHANGELOG.md) if users will notice the change.
6. Open a pull request and fill in the template.

## Guidelines

- **Match SwiftUI.** Public API must have the same names, signatures, and behavior as SwiftUI.
  When SwiftUI's behavior is undocumented, describe what you observed on Apple platforms in the
  pull request. Parhelion-only API belongs in `ViewHost` and `ViewNode`, not on views.
- **No Apple code.** Do not copy source code, headers, or assets from Apple's SDKs. Implement
  from public documentation and observed behavior only.
- **Swift 6 language mode.** The package builds with strict concurrency checking and no warnings.
- **Small pull requests.** One logical change per pull request is easier to review and revert.
- **Commit messages.** Write the subject in the imperative mood ("Add HStack spacing"), at most
  72 characters, with details in the body when they help.

## Use of AI tools

Parhelion is built for coding agents, and you are welcome to use them for contributions. You are
responsible for everything you submit:

- **Disclose it.** Choose the AI assistance level in the pull request template that is true for
  your change. If no person has reviewed the change line by line, choose *Generated, not
  reviewed*, and open the pull request as a draft unless you are a maintainer.
- **Own it.** Answer review questions yourself, and fix what the review finds.

## Review and merging

A maintainer reviews every pull request. CI must pass before merge. Pull requests are merged
with squash commits, so the pull request title becomes the commit subject. Maintainers label
merged pull requests so that release notes group them by type; see
[docs/releasing.md](docs/releasing.md).

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE), the same license as the project.
