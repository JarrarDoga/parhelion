# 0002: Defer the choice of renderer backend

- **Status:** Superseded by [0004](0004-pure-swift-renderer.md)
- **Date:** 2026-10-19

## Context

Parhelion will draw apps in a phone-sized window on Linux. Candidate backends include Vulkan
directly, a 2D library such as Skia or ThorVG on top of Vulkan or OpenGL, and a CPU rasterizer
for headless screenshots. They differ in text quality, dependency size, how easily they build in
CI, and how closely they can match SwiftUI's drawing.

The backend must meet these requirements:

- Draw into a native window on Linux, under both Wayland and X11.
- Draw into off-screen frames at interactive rates, so another tool, such as an agent's
  workspace, can embed or stream the preview.
- Render text well enough to judge a layout.
- Build in CI without a GPU, for screenshot tests.

Choosing now would mean choosing before there is a layout pass to feed the renderer, and before
we know which drawing operations the supported views need.

## Decision

Build the layout pass before the renderer. Keep the boundary fixed: a renderer consumes a
laid-out `ViewNode` tree, which is plain data, and never reads view values. Choose the backend
during milestone 0.2, as soon as layout produces frames, and record the choice in a new ADR that
supersedes this one.

## Consequences

- The headless runtime, tests, and agent tooling do not depend on a GPU, a display server, or
  native graphics libraries. CI stays simple.
- The renderer can be replaced later without changes to views or state, because it depends only
  on the tree.
- Until the backend exists, Parhelion cannot show a window or produce screenshots. The roadmap
  puts the renderer and the preview window in 0.2.
