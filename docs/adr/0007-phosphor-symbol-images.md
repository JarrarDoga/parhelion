# 0007: Draw SF Symbol names with Phosphor Icons, embedded as SVG path data

- **Status:** Accepted
- **Date:** 2026-10-23

## Context

SwiftUI apps name their icons with SF Symbols: `Image(systemName: "house")`, `Label("Home",
systemImage: "house")`, and `Tab("Home", systemImage: "house")`. Until now Parhelion drew every
symbol except the back button's chevron as a ring, which made tab bars, toolbars, and labeled rows
hard to read.

Apple's license allows SF Symbols only in software for Apple platforms, so Parhelion cannot ship
them. Phosphor Icons is an MIT-licensed set of about 1,500 icons in several weights, including
regular and fill, published as SVG files (`@phosphor-icons/core`) and as icon fonts. Its regular
weight is a single filled outline per icon on a 256-unit grid, which suits the renderer's
nonzero fill.

Parhelion cannot ship SwiftPM resources ([ADR 0003](0003-no-swiftpm-resources.md)), so the icons
must be compiled into the library. We compared two forms for the 245 icons the mapping needs, in
two weights each:

- SVG path data from the core package: about 170 KB of source, exact geometry with arcs and cubic
  curves, and a generator that needs only `sed`.
- A subset of the two icon fonts, base64-encoded: about 170 KB of source, read by the existing
  TrueType parser, but with curves reduced to quadratics, and a generator that needs fontTools.

## Decision

- `Symbols/symbols.txt` maps SF Symbol names to Phosphor icon names. A name with a `.fill` suffix
  draws the fill weight of its base name's icon.
- `Scripts/embed-symbols.sh` reads the extracted `@phosphor-icons/core` package and writes the
  mapping and the path data, unchanged, to `Sources/ParhelionUI/PhosphorSymbolData.swift`. It
  includes only mapped icons, in the regular and fill weights. Phosphor's license is in
  `Symbols/Phosphor-LICENSE.txt`, and `NOTICE` credits it.
- `Path(svgPathData:)` in `ParhelionRender` parses the data on first use, and the parsed outlines
  are cached.
- `SymbolLibrary.resolve(_:weight:scale:fill:)` is the only lookup. It returns an outline in a unit
  square and the source that drew it: built-in chevrons, Phosphor, or a placeholder ring.

## Consequences

- Common symbols are recognizable in screenshots, and agents can tell from the tree when a name is
  not drawn: its node records `missingSymbol=true`.
- Symbols look like Phosphor's, not Apple's: strokes are rounder, and some icons differ in detail.
  Every font weight draws Phosphor's regular weight.
- Names outside the mapping draw as rings until someone adds them to `symbols.txt` and runs the
  script. CI cannot check the generated file against the package, because it does not download
  it; the script's header names the package version.
- Another source can go in front of Phosphor, such as the SF Symbols on a developer's own Mac,
  by changing only `SymbolLibrary`.
- The generated source adds about 190 KB to the repository.
