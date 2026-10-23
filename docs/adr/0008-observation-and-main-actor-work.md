# 0008: Views observe models with the toolchain's Observation, and the app runs main-actor work while it waits

- **Status:** Accepted
- **Date:** 2026-10-23

## Context

Most new SwiftUI apps keep their model in `@Observable` classes, load data in `task`, and start
`Task`s from buttons. Parhelion has to update the tree when a model changes and has to run that
asynchronous work, on Linux, without a window, and deterministically enough for tests and agents.

Swift ships the Observation module, with the `@Observable` macro and `withObservationTracking`,
in every toolchain on Linux. Apple's SwiftUI uses the same module, so a model written for iOS
compiles and behaves the same. Swift 6.4 added cancellable tracking, but Parhelion also builds
with Swift 6.3, where only the one-shot `withObservationTracking(_:onChange:)` is public.

Before this change, an app's main thread blocked on the preview socket between messages, so work
queued for the main actor ran only when a message arrived.

## Decision

- `import SwiftUI` re-exports the toolchain's Observation module. Parhelion has no Observation of
  its own.
- Each evaluation of the tree runs inside one `withObservationTracking`. A change to any property
  it read marks the host as needing an update, synchronously when the change happens on the main
  actor. Observation installs its observers after the evaluation, so the previous evaluation's
  tracking stays active until the new one is installed. Each evaluation reads one of two private
  observable values, and changing the one the previous evaluation read retires its tracking
  without Swift 6.4's cancellation.
- In a preview session, a background thread receives the host's messages, and the main thread
  waits in the main run loop, which runs main-actor work while nothing arrives. A session run by
  a test, which is itself main-actor work, only waits for messages.
- `task` work is tracked by the host: `ViewHost.pendingTaskCount`, `ViewHost.waitForTasks()`, a
  count in every reply to an agent, and a `wait` tool that returns when the work finishes. Other
  `Task`s are not tracked.

## Consequences

- Models behave as on Apple platforms, including `withAnimation` around a model change, and a
  model change made on another thread is applied on the main actor's next turn.
- The whole tree is still evaluated on every update. Tracking one evaluation as a whole is what
  makes that cheap to keep correct; per-view tracking can come with incremental evaluation.
- Tests wait for asynchronous work with `await host.waitForTasks()` instead of sleeping.
- Messages take one more thread hop, about 10 µs. The main run loop is the only place where the
  app waits, so anything that blocks the main thread elsewhere stops both input and main-actor
  work.
- Replacing Observation, or moving work off the main run loop, would change how every app is
  updated, so it is recorded here.
