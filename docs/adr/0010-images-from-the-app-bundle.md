# 0010: Images come from the app's raw asset catalog, decoded in pure Swift, through a side table

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

`Image("name")` draws an image from an app's `Assets.xcassets`. On Apple platforms, Xcode or
`actool` compiles the catalog into `Assets.car`, and `UIImage` reads it. Parhelion has neither, and
it cannot ship SwiftPM `resources:` itself ([ADR 0003](0003-no-swiftpm-resources.md)).

On Linux, Swift 6.4.1's default build system treats an asset catalog in an app's target as a
resource with no rule to process it: it copies the folder, unchanged, into the target's
`<Package>_<Target>.bundle` beside the executable and generates `Bundle.module` (measured for
issue #30's research, section 4.2). `parhelion run` builds an `xtool`-shaped app through a
runner package, so there the bundle is `ParhelionRunner_<Target>.bundle`. Apps write
`Image("name", bundle: .module)`, as xtool's documentation shows, or `Image("name")`.

The renderer and layout read only the tree ([ADR 0005](0005-model-tree-and-presented-frames.md)),
whose attributes are strings, and tests assert on `outline()`, so the tree cannot hold pixels or
paths that differ from machine to machine.

`AsyncImage(request:)` and `asyncImageURLSession(_:)` name `URLRequest` and `URLSession`, which
Apple's Foundation provides. On Linux they are in FoundationNetworking, which links libcurl.

## Decision

- Parhelion reads the raw catalog at run time: each image set's `Contents.json` and its files,
  with groups, namespaces, 1×, 2×, and 3× files, dark appearances, and
  `template-rendering-intent`. `Image(_:bundle:)` looks in the given bundle; with no bundle, or
  the main one, it looks in the main bundle's folder and every `*.bundle` beside it, because an
  app's catalog is never in the main bundle on Linux.
- `ParhelionRender` decodes PNG in pure Swift, with its own inflate
  ([ADR 0004](0004-pure-swift-renderer.md)). JPEG, PDF, and HEIF files draw as missing images.
- The tree records what layout and agents need, with machine-independent values: `name`,
  `bundle` (the bundle folder's name without `.bundle`, only when the app passed a bundle),
  `size` in points from the largest file's PNG header, `appearance=dark`, `renderingMode`, and
  `missingImage`. An `AsyncImage`'s image records its `url`.
- Pixels stay out of the tree. `ImageLibrary`, a table shared in the process, finds image sets by
  bundle and name, decodes files, keeps up to 256 MB of them, and keeps the images `AsyncImage`
  loaded by URL. The renderer looks images up there from the node's attributes. Shapes of an
  app's own types work the same way: `CustomShapes` keeps them by the description the node
  records, so the renderer can ask for a path in the frame layout chose.
- `import SwiftUI` re-exports FoundationNetworking on Linux, so `URLRequest` and `URLSession` are
  available as they are under Apple's SDK. `AsyncImage` reads `file:` URLs from disk and loads
  others with `URLSession`.

## Consequences

- Images work in `swift run`, `parhelion run`, `--png`, tests, and agents without a build step,
  and a catalog that Xcode wrote works unchanged. Whether xtool compiles the same catalog for an
  iOS build is up to xtool; `Scripts/check-ios-build.sh` builds an app with one.
- Drawing an image reads state that the tree does not hold. The library is keyed only by values
  the tree records, and files do not change while an app runs (hot reload starts a new process),
  so the same tree still draws the same pixels. A cache entry that was evicted is decoded again;
  an `AsyncImage` image that was evicted draws as missing until the view loads it again.
- A shape of an app's own type must draw the same path for the same description. One whose path
  depends on something `String(describing:)` does not show would draw the wrong path.
- Every app on Linux links FoundationNetworking and so needs libcurl at run time, which Swift's
  Linux toolchains already require for `URLSession`.
- Adding JPEG or HEIF means adding a decoder to `ParhelionRender`; nothing else changes. Reading a
  compiled `Assets.car` would be a separate decision.
