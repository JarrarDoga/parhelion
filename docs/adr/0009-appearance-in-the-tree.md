# 0009: The tree records the color scheme and the text size, and preferences take a second pass

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

Dark mode and Dynamic Type change how every color and font resolves. The renderer and layout
read only the tree ([ADR 0005](0005-model-tree-and-presented-frames.md)), and tests, agents, and
the README assert on `outline()`, so whatever the renderer and layout need has to be in the
tree, under names that stay stable.

`preferredColorScheme(_:)` is a preference: it flows up from a view to its presentation, which
then draws everything in it, including views evaluated before the modifier, in that scheme.
Parhelion evaluates the tree in one pass.

The preview window, web pages, and agents switch the setting while an app runs, and an app may
be built against an older Parhelion than the tool.

## Decision

- `ViewHost.colorScheme` and `ViewHost.dynamicTypeSize` are the simulated device's settings.
  They are Parhelion-only API on `ViewHost`; views see only SwiftUI's environment values.
- The tree records three attributes, with SwiftUI's case names:
  - `colorScheme` (`light` or `dark`) on the root while the window is not light, on a
    presentation whose scheme differs from the window's, and on the nodes an environment writer
    returns when it changes the scheme;
  - `dynamicTypeSize` (such as `xxxLarge` or `accessibility2`) in the same places for the text
    size, with `large` as the root's default;
  - `fontSize`, in points, on a `Text` or a symbol `Image` whose size differs from its font's size
    at Large. `font` keeps naming the style, so `font=title fontSize=34` is a title at xxxLarge.
- The renderer inherits `colorScheme` down the tree. Layout and drawing find a text style's line
  height from its name and `fontSize`, since every size of a style has one line height.
- A presentation's preference is collected while the presentation is evaluated, and used from
  the next evaluation on. When a pass finds a different preference, the host evaluates again in
  the same update, through the bounded update loop.
- The preview protocol gains `PreviewCommand.setAppearance(colorScheme:dynamicTypeSize:)` and the
  `appearance` capability, which the host reads from the hello without a welcome. The tool keeps
  the setting and passes it to every launch in `PARHELION_COLOR_SCHEME` and
  `PARHELION_DYNAMIC_TYPE_SIZE`.

## Consequences

- Outlines show where a scheme or a size begins, and light screens at Large outline exactly as
  before, so existing tests and README images did not change.
- Changing a preference costs one extra evaluation, only in the update where it changes.
- The attribute names are part of the tree's contract: renaming them breaks tests and agents'
  expectations, and any future attribute that depends on the scheme or the size must use them.
- An app built with an older Parhelion ignores the environment variables and does not list the
  capability; the tool says the app cannot switch instead of sending a command it cannot decode.
