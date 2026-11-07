# 0011: A manual clock for agents: `wait` advances the app's time, and replaced executors hold `Task.sleep`

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

An agent that calls `wait` on `parhelion mcp` without a window waited in real time. A `task` that
slept 5 seconds, a loading banner, or a debounce cost the agent 5 seconds each, and a `Task` that
a button started had no tracking at all, so `wait` could only sleep the whole time and hope.

Parhelion already owns part of the app's time: `ViewHost.time` moves only through
`advanceTime(by:)`, and animations and scroll momentum follow it. `Task.sleep` is different. Since
Swift 6.3, every `Task.sleep` reaches the executor that is current for the task through the
experimental `SchedulingExecutor` API. The old runtime hook (`swift_task_enqueueGlobalWithDeadline_hook`)
sees none of them. A custom `Clock` helps only code that is handed the clock, and SwiftUI code
writes `Task.sleep(for:)`. A task executor preference (SE-0417) reaches `.task` and structured
children but not `Task { }` or `Task.detached { }`. The research for #31 (experiments `drain3.swift`,
`executor.swift`, `hop-trace.swift`, `mainonly.swift`) found that only replacing both the main and
the default executor, at the start of `main`, intercepts every sleep: a main-actor sleep first hops
to the global pool, so replacing only the main executor holds nothing.

## Decision

**A `manualClock` capability.** An app started with `PARHELION_MANUAL_CLOCK=1` lists
`manualClock` in its hello. The host welcomes it only when it shows no frames: `parhelion mcp`
without `--window` or `--web`, and later `parhelion test`. A welcomed app never moves its clock
to real time and never draws on its own schedule. It moves time only for the new
`advanceTime(seconds:)` command. Window hosts do not offer the capability, so a window or a page
keeps real time and `wait` behaves as before ([ADR 0006](0006-host-clock-and-shared-frames.md):
changed clock semantics need a new capability name).

**Replaced executors.** `App.main()` calls `_createExecutors(factory:)` first, under
`#if compiler(>=6.3)`, when the variable is set. `HostClockMainExecutor` queues main-actor jobs in
a FIFO. `HostClockExecutor`, the default executor, queues other jobs in a second FIFO and holds
each `Task.sleep` wake-up at "virtual now plus the delay", the delay rounded up to the
millisecond because the deadline is read before the call. Both FIFOs are drained on the main
thread, from the main queue when nobody advances time, so the process stays deterministic: in the
experiment, 50 of 50 runs gave the same order.

**`advanceTime`.** For each held wake-up up to the target, in deadline order (ties in the order
they went to sleep), the host moves `ViewHost.time` to the deadline with `advanceTime(by:)`, runs
the wake-up, drains both FIFOs, and updates the tree. Then it moves to the target. MCP `wait`
sends the command and returns at once; the reply adds when the next timer fires. A task that
waits for something other than time (a socket) gets up to 250 ms of real time once no sleep is
left. The headless runner (`--png`, the printed tree) uses the same advance for its five seconds
of `task` work.

## Consequences

- Animations, scroll momentum, `Task.sleep` in `task` actions, `Task`s, and detached tasks all
  reach the state they would after the time passed, and a 10-second `wait` over a 5-second sleep
  takes milliseconds.
- **It depends on SPI** (`ExperimentalCustomExecutors`, `ExperimentalScheduling`). SE-0505
  ("Delayed Enqueuing for Executors") is *Returned for revision*, so a later toolchain may
  rename or remove it. The fallback is option A of the research: build without the SPI, return
  `false` from `ManualClock.install()`, and the tool keeps real-time `wait`. Only `Task.sleep` is
  lost; animations and momentum stay on `ViewHost.time`. Swift 6.3 and 6.4 behave the same, and
  a test that starts an example as a process checks both in CI.
- **Global-pool work runs serially on the main thread** while the clock is manual. App code that
  blocks a thread to wait for another task deadlocks, the hazard `withMainSerialExecutor`
  carries. Only agent sessions and replays are affected.
- Foundation `Timer`, `DispatchQueue.asyncAfter`, `Date()`, and `ContinuousClock.now` stay on real
  time. `TimelineView` (#72) and long-press durations (#56) read `ViewHost.time` instead.
- A cancelled sleep leaves its wake-up held until its deadline. That is harmless, but
  `nextWake` can name the deadline of a task that no longer waits.
- The Swift Testing runner owns its `main`, so unit tests cannot install the executors. The
  clock is tested in a separate process, the way a host starts an app.
