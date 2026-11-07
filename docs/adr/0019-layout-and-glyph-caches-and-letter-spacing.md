# 0019: Layout sizes, glyph outlines, and text lines are kept between frames, and text has letter spacing

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Rustle's Collection screen scrolls 5,000 rows of art and two lines of text, and Now Playing animates
over large art and glass. At 120 Hz a frame has 8.3 ms. Measured on those shapes (see the pull
request), layout spent most of its time measuring text and the same nodes again for each proposal,
and drawing spent most of its time reading glyph outlines from the font and rasterizing them.

Inter is also wider than San Francisco at the sizes iOS text uses, so a line that fits on the phone
can wrap in the preview.

## Decision

- **Sizes.** `LayoutEngine` keeps the size it chose for a node in a `SizeCache`, by node
  identifier, the number of the node's modifiers that were applied, the proposal, and the parent's
  axis. An entry is used only when the node being measured is equal to the node measured then, so
  an edit to a node is never answered with a stale size. A size that read layout state outside its
  node, such as the lengths a lazy stack has measured, and every size computed around it, is not
  kept. Entries live as long as the host's engine.
- **Text lines.** `FontTextMeasurer` keeps the lines of a string by string, size, weight, and width
  in a cache shared by every measurer.
- **Glyph outlines.** A `TrueTypeFont` keeps the outline of each glyph it has parsed.
- **Glyph coverage.** A font keeps the anti-aliased coverage of a glyph by size in pixels and by
  position within a pixel, to a quarter of a pixel. `Canvas.drawText` composites those instead of
  rasterizing a line's outline in every frame. A glyph sits at the nearest quarter pixel, so a line
  differs from one rasterized whole by less than an eighth of a pixel at every glyph.
- **Drawing paths.** Shadows, gradients, and layers have fast paths for the pixels that need no
  mixing. A shadow blends four pixels at a time with integer vectors over opaque pixels, and
  skips the faint tail of its blur. A rounded rectangle filled with a gradient rasterizes only its
  corners and stores a whole run of fully covered pixels, from a table with a step for each half
  pixel along the gradient. A layer is copied four opaque pixels at a time, and text blends with
  the integer path that shadows use. These round a level differently from `blend` in some pixels,
  never by more than one level in a channel.
- **Letter spacing.** Every character is followed by `-0.0223 + 0.185 * exp(-0.1745 * size)` em,
  the tracking in Inter's own dynamic metrics. Measuring and drawing both use it.

## Consequences

- Layout after a scroll or an animation frame measures only what changed. Equal nodes share storage
  when the host lays the same evaluated tree out again, so checking a hit is quick.
- The caches are bounded: 50,000 sizes, 16,384 lines of text, and 24,000 glyph coverages. A cache
  that fills starts over.
- Letter spacing narrows text by about 1 to 2 percent at body size, and every text width in the
  preview changes with it. The README images and the stored snapshots were recorded again.
- The tracking curve is Inter's, not San Francisco's. No San Francisco font is available on Linux
  to measure against, so the curve brings widths toward SF's without having been fitted to them.
  Replace `TrueTypeFont.tracking(size:)` when measured widths exist; nothing else depends on the
  curve.
- Glyph coverage at quarter pixels, and the integer blends, change edge pixels slightly compared
  with rasterizing a whole line and blending in floating point, which is why the images were
  recorded again together.
- What these changes do not reach: scrolling the Collection fixture still redraws every row, the
  scroll edge effect, and the title bar in each frame. Drawing only the strip a scroll exposes
  needs the canvas to keep the previous frame, and that is left for a later record.
