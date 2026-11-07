# 0021: Draw the user's own SF Symbols, exported as SVG, in front of Phosphor

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

[ADR 0007](0007-phosphor-symbol-images.md) draws SF Symbol names with Phosphor Icons because
Apple's license forbids shipping SF Symbols outside Apple platforms. A person who builds iOS apps
can have their own copy, and would see their real symbols in the preview. Parhelion must not
contain, download, or redistribute them, and CI and tests must not need them. No copy was
available when this was written, so the sources below come from other projects' public notes,
not from opening Apple's files.

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
