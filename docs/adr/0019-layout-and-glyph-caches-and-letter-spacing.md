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
- **Scrolling moves the last frame.** `RenderCache` keeps the pixels a scroll view's content
  drew in the last frame. When the content moved by a whole number of pixels and the view
  beneath it is one flat color, the next frame copies those pixels shifted by the scroll and
  draws again only the rows that came into view and the nodes whose description changed (found by
  comparing the content with the last frame's, node by node, moved by the scroll), with the
  other nodes culled by their bounds. Content that reads the pixels around what it draws (glass,
  blurs, the scroll edge effect; `Canvas.readsSurroundings`), or that scales or transforms nodes
  that changed, is drawn in full, as is a frame in which more than 60 percent of the rows are
  new. A kept frame equals a full one, which `ScrollShiftTests` checks frame by frame at 2× and
  3×; at 3× a gradient's step can differ by one level in a pixel, because a whole pixel is not a
  whole number of 1/1024 points.
- **Scrolled content is placed on pixels.** The renderer moves a scroll view's content so that its
  origin is a whole number of pixels, as a scroll view on a device does, and rounds every
  coordinate in it to 1/1024 of a point. Two frames then differ by whole pixels, with exact
  coordinates, so the same node draws the same pixels wherever it is. This changes the pixels of
  every scroll view's content by a fraction of a pixel, and the README images were recorded
  again.
- **A shadow does not depend on its clip.** The grid of samples a shadow is blurred on began at
  the clip's edge, so the same shadow had different pixels (by one level) under different clips.
  It now keeps its own grid, which a smaller clip moves only by whole samples.
- **Layout skips the animation comparison while scrolling.** A scroll or a step of momentum, with
  no animation running or requested, does not compare the old tree with the new one for views that
  start to animate, since none can.
- **Threads.** Passes over the rows of a large canvas run on up to four threads, when there are
  enough rows to repay starting them: filling a canvas, copying and checking the rows of a kept
  frame, a rounded rectangle's gradient, the blend of a layer's shadow and of a layer, the
  blur of a shadow's samples, and the scroll edge effect's resampling. Each thread writes its own
  rows, so the pixels are the same as without threads.
- A shadow of a layer is not blended where the layer is opaque and drawn over it next, which is
  most of a large shadow's area.

## What the measurements say

The `present at` gaps and the times per frame are in the pull request. At the preview's default
scale (2×), the Collection fixture's frame takes about 5 ms to draw and 1.4 ms to lay out, and
Now Playing's takes about 7 ms. The window host presents a frame every refresh when the app
answers within one refresh less its upload and a margin, and the pacer looks at the slowest of the
last 16 answers, so a single slow frame keeps the host at two refreshes for 16 frames. At 3× the
same work covers 2.25 times the pixels; the CPU renderer does not reach 8.3 ms there for the
screens measured.
