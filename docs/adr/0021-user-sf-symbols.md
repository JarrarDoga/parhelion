# 0021: Draw the user's own SF Symbols, exported as SVG, in front of Phosphor

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

[ADR 0007](0007-phosphor-symbol-images.md) draws SF Symbol names with Phosphor Icons because
Apple's license forbids shipping SF Symbols outside Apple platforms. A person who builds iOS apps
can have their own copy, and would see their real symbols in the preview. Parhelion must not
contain, download, or redistribute them, and CI and tests must not need them. The first draft
came from other projects' public notes; the findings from a real copy (SF Symbols 27, opened on
2026-11-08) are at the end.

Candidate sources in a user's copy:

- **The SF Symbols app's own data.** Names and outlines live in `CoreGlyphs.bundle`, in an
  `Assets.car` asset catalog that only Apple's frameworks open (the `sfsym` tool reads it through
  AppKit's private API), and in an encrypted table of the SF fonts. Parhelion cannot read either on
  Linux, and reading around the encryption is out of the question.
- **The symbols in SF Pro, at private-use code points** (U+100000 and up). CoreText has no glyph
  names for them, so the name-to-glyph map must come from elsewhere, and the layout of the fonts
  changed in SF Symbols 2. Weights are variable-font axes or separate files, and the outlines may
  be CFF, which the renderer does not read.
- **SVG exports.** The app's File > Export Symbol writes a template per symbol: one `g` element
  per weight and scale, with ids like `Regular-M` and `Ultralight-S`, each holding the outline as
  path data. The file name is the symbol's name, and `.fill` variants are their own symbols.
  The format is documented for designers and needs no private API.

## Decision

- Parhelion reads **SVG exports**, one file per symbol, from a folder. `SymbolTemplate`
  (`ParhelionRender`) reads the medium-scale group of each of the nine weights; the symbol's frame
  already has the size of its image scale. `Path(svgPathData:)` parses the data.
- The folder is `$PARHELION_SF_SYMBOLS` when set, otherwise
  `$XDG_DATA_HOME/parhelion/symbols`, or `~/.local/share/parhelion/symbols`.
- `parhelion symbols import PATH` takes a folder of exports, searched recursively, or one SVG
  file. It keeps only the medium-scale outlines, writes them to the folder, and refuses a
  destination inside a Git repository. A path to an `.app`, a disk image, or an archive fails
  with directions for exporting from the app, because those cannot be read (above).
  `parhelion symbols status` says which folder is read.
- `SymbolLibrary.resolve` asks `UserSymbols` first, then Phosphor, then the placeholder. The font
  weight picks the weight of the export, with the nearest present weight standing in for a
  missing one. A symbol drawn with the fill variant (the tab bar's) uses `NAME.fill` when the
  folder has it, and otherwise `NAME`. A `.fill` name with no file of its own falls to Phosphor.
- A symbol drawn from the folder records `symbolSource=sfSymbols` in its node. Phosphor is the
  default and adds no attribute, so trees without a copy do not change.
- `Scripts/check-no-sf-symbols.sh` runs in CI's lint job. It fails if Git tracks SVGs with an
  export's group ids, or files named like Apple's symbol data and fonts. Tests use a synthetic
  export of squares.

## Consequences

- Without a folder, nothing changes: symbols are Phosphor's.
- A person must export from the app once. The import keeps only the medium-scale outlines of
  each export, so the folder is smaller than the exports.
- The size is assumed: an export draws at 100 units to the em, and the medium scale is drawn at the
  size of its font, centered on each weight's bounds. Compare against a real copy and adjust the
  `unit` in `UserSymbols` if a symbol looks off.
- Layers, hierarchical and palette rendering, and symbol effects are not used: each symbol is one
  outline in the foreground style.
- The license question stays with the user, and the README says so.

## Findings from a real copy

SF Symbols 27, the DMG from Apple's site, unpacked on Linux with 7z and cpio:

- The app holds `Resources/Fonts/SFSymbolsFallback.otf`, a variable CFF2 font with a weight axis,
  whose 10,513 symbol glyphs sit at U+100000 and up with names like `uni100000.medium`. The map
  from symbol names to those code points is in private tables (`symp`, `syls`, `syot`) that are
  encrypted. `Library/Fonts/SF-Pro.ttf` is TrueType with 8,564 such glyphs and no names either.
  The metadata plists list the 9,649 names, their releases, and their aliases, but no code points.
- The app also holds a command-line tool, `Contents/Executables/sfsymbols`, whose `export`
  subcommand writes the same SVG templates as File > Export Symbol, for a list of names in one run.
  On an M4 MacBook Air it exported all 9,649 in a few minutes, about 200 MB of SVG.
- Each template holds three groups, `Ultralight-S`, `Regular-S`, and `Black-S`, with the same
  points in each, so Apple interpolates the other weights. The reader takes the medium scale when
  an export has it and otherwise the small scale, enlarged by 1 / 0.78 to medium, and interpolates
  a missing weight between the nearest two present ones when their outlines match point for point.
  The import keeps those groups, about 65 MB for all symbols.

