# 0015: Gestures are recognized by the host from the pointer, and arbitrated in one place

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Rustle's mini player swipe, cover pager, row long press, stretch handle, and scrubber thumb need
`TapGesture`, `LongPressGesture`, `DragGesture`, and their combinations. A drag has to follow the
pointer one to one, a long press has to fire after its minimum duration with no further input, and
a pager has to take a swipe inside a vertical `ScrollView` without scrolling it. Until now the host
had one hard-coded rule per control: a button taps on release, a slider follows the pointer, a
press that moves more than 10 points scrolls.

## Decision

- **A gesture is a description; a recognizer is its state for one press.** `makeRecognizer(for:)`
  turns a `Gesture` value into a tree of recognizers (`GestureRecognizers.swift`). A recognizer
  takes pointer events and the host's clock and answers with events (changed, ended, failed) that
  carry the user's callbacks as effects. It does not run the callbacks itself.
- **The modifier marks the node.** `gesture`, `onTapGesture`, and the others add a no-op custom
  modifier (`gesture`) to the content's nodes, so the outline shows them and `modifierFrames` gives
  the gesture's area: the bounds at that point in the modifier chain, so padding added after the
  gesture is outside it. The recognizer factory goes to `ViewHost.gestures`, keyed by node and by
  the gesture's place among the node's gesture modifiers.
- **The host builds a session on pointer down** from the nodes under the press, root to leaf. Order
  of precedence: `highPriorityGesture` first; then the deepest view first, inner modifiers before
  outer ones; a button, link, or text field comes after the gestures on its own view (a gesture put
  on a button replaces its action, a gesture on a view around it yields to the button).
  `simultaneousGesture` recognizers are fed regardless and neither block nor are blocked.
  `GestureMask` cuts gestures off as in SwiftUI.
- **Arbitration.** Recognizers are asked in order of precedence. What a recognizer reports waits
  while one with higher precedence could still win (a drag before its minimum distance, a double
  tap after its first tap). When a recognizer is recognized, the lower ones are cancelled; a long
  press also cancels the higher ones, since holding is not tapping. Callbacks run only when the
  host lets an event through, and a cancelled gesture puts back its `GestureState`.
- **Scroll views and sheets take part.** Once a press moves past the drag threshold, it turns into
  a scroll or a sheet drag only if no gesture inside that view (or with priority) has it or could
  still get it. Gestures on and outside the scroll view wait until it decides, then end if it takes
  the press. A simultaneous gesture carries on.
- **Time comes from `ViewHost.time`.** `advanceTime(by:)` ticks the session, so a long press fires
  at its minimum duration under the manual clock ([ADR 0012](0012-manual-clock.md)) and in a
  window alike, and a multi-tap times out after 0.35 s.
- **MCP.** `drag` already took a duration. `long_press` is a registered tool
  ([ADR 0011](0011-extension-seam.md)) that runs the app's `drag` command from a point to itself.

## Consequences

- Nothing changes for an app that attaches no gesture: no session is built.
- Behavior that differs from a device is chosen, not measured: a drag's `predictedEnd` projects half a
  second of velocity (UIScrollView's normal deceleration), a tap allows 10 points of movement, a
  button inside a view with gestures stops being a tap once the press moves 10 points, and
  `.named` coordinate spaces read as the screen's until `coordinateSpace(name:)` exists.
- A press that is a multi-tap in waiting keeps the session alive, so `isAnimating` is true for up to
  0.35 s after a tap on a view with a double tap.
- The recognizers hold no references to nodes. The cost per pointer event is one pass over the
  session's items; pointer down costs one walk of the tree when any view has a gesture.
