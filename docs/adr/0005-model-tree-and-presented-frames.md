# 0005: The view tree holds final values; animation affects only what is drawn

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

Animations add a second state to every node that is moving: where it is drawn now, and where it
will end up. `ViewHost.root` is the contract that tests, agents, hit testing, and the renderer all
read, so it can hold only one of them.

Navigation and presentations animate implicitly. If `root` held the frames on screen, every read
of the tree right after a tap that pushes a screen or opens a sheet would contain the departing
screen next to the arriving one, at intermediate positions. Every test and every agent would have
to advance or wait for time before reading the tree, and identical sequences of taps would give
different trees depending on when the tree was read.

iOS separates the two states. Core Animation keeps a model layer, which holds the values the app
set, and a presentation layer, which holds the values on screen. UIKit hit-tests the model layer
during implicit animations.

## Decision

- `ViewHost.root` holds final values. Frames, opacities, and the set of nodes change as soon as
  the state changes, and hit testing uses them.
- `ViewHost.presentedRoot` is the tree as drawn at the host's current time: `root` with the
  animations in progress applied, including nodes that have left `root` and are still
  transitioning out. The renderer draws it. It equals `root` when nothing is animating.
- `isAnimating` reports that the two differ, and `revision` increases while they do, so clients
  know to keep drawing. The MCP server tells agents to wait before taking a screenshot while the
  screen is animating.

## Consequences

- Tests and agents read a stable tree right after an interaction, without stepping the clock.
  The existing test suites passed unchanged when animations were added.
- A screenshot taken during an animation shows a frame that the tree does not describe. Agents
  call `wait` first; tests that check animation read `presentedRoot`.
- A tap during an animation goes to where a view is going, not where it is drawn, as on iOS.
- Changing this later would change what every client reads, so it is recorded here.
