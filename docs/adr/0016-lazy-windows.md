# 0016: Lazy stacks and lists evaluate a window of rows that layout asks for

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Rustle's main playlist has 1,535 songs, and the target is 5,000. Parhelion evaluates the whole view
tree on every update and lays out every node, so a 5,000-row `List` costs seconds per scroll step.
SwiftUI's `LazyVStack`, `LazyHStack`, and `List` create only the rows near the screen.

Which rows are near the screen depends on layout: on the scroll offset, the scroll view's size, and
the height of every row above. But Parhelion evaluates first and lays out second, and scrolling
lays out again without evaluating.

## Decision

- **Slots.** A lazy container flattens its content into *slots* without evaluating them: a
  `ForEach` is one segment with a count, an identity for each element, and a function that
  evaluates one element. `TupleView`, `if`, `Group`, and `Section` are looked through; any other
  view is one slot.
- **Window and demand.** Evaluation creates the slots in a *window*. Layout measures them, keeps
  every slot's length by identity, uses the mean length for slots that do not exist, and records
  the slots that overlap the scroll view, the *demand*. After each layout, the host compares the
  demand with the window. If the demand is outside it, the host evaluates again, which makes a new
  window around the demand with a margin of half a scroll view on each side, and lays out again.
  A window that still covers the demand is kept, so scrolling re-evaluates once every few rows,
  not on every frame.
- **Identity and state.** A slot's node ids and `@State` keys come from the same structural path as
  in eager evaluation (`LazyVStack/ForEach[42]/Row`). The host keeps the state of a released row
  while its identity is in the data, as the issue requires, and discards it when the identity goes.
- **Lists.** A `List` with no more than 40 rows is evaluated as before, so its tree is the same.
  A longer one makes its sections lazy: a `Section` node that holds only some of its rows records
  `lazyCount` and `lazyResolved`, and layout sizes it with the lengths of all its rows. Drawing is
  unchanged, since it reads the rows that exist. A list that holds views that make `Section`s,
  such as a `ForEach` of `Section`s, is evaluated in full.
- **Where it plugs in.** `LazyVStack` and `LazyHStack` register their kinds through the extension
  seam ([ADR 0011](0011-extension-seam.md)). A list's `Section` is a built-in kind, so layout asks
  the lazy code first when the node has `lazyCount`: two lines in `LayoutEngine.swift`, as
  are the viewport that `placeScrollView` pushes and the `lazy` property of `ScrollLayout`.

## Consequences

- The tree, `outline()`, and the MCP tools show only the rows that exist. An agent that needs a
  row far down scrolls with `scroll_to`, which sets an offset, and the next update creates the row.
- Evaluation is still a full pass, but it now costs the rows in the window plus the rest of the
  tree, not every row. Each window change is one such pass.
- A row's length is unknown until it exists. A list of rows of different heights can shift by the
  difference between the mean and the real length when rows above the screen are created. Rows of
  one height, the common case, do not shift.
- Row lengths are kept for one width. When the width changes, they are measured again as rows are
  created.
- `onAppear` and `task` run when a row is created, a margin before it is visible, and `onDisappear`
  runs when it is released. SwiftUI's timing differs by an amount it does not document.
- A lazy stack outside a scroll view uses the screen as its viewport.
