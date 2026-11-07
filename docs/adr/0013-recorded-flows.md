# 0013: Recorded flows are JSON that the app records and replays

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

A person can check a run through an app's screens in the preview window, but only once. Xcode
records UI tests as Swift, Playwright's codegen writes test code, and Maestro runs hand-written
YAML. Parhelion needs the same loop for CI: record a run once in the window, replay it headless
on every change. The research for #31 (section 3) compared the options.

The window host sees only points (`pointerDown(x:y:)`). The app knows which control a release hit
and that control's identifier and label. Parhelion's root package has no package dependencies, and
Foundation has no YAML parser. `PreviewCommand` is `Codable` already and is what the agent tools
send.

## Decision

**A `Flow` is JSON**: a `version`, a `device`, and `steps`, each `command(PreviewCommand)`,
`wait(seconds)`, or `expect(outline)`. The file has its own `version`, because the protocol's
command names are a wire format that [ADR 0006](0006-host-clock-and-shared-frames.md) versions
apart from it. A reader refuses a newer version. Checkpoints are lists of lines.

**The app records.** `PreviewSession` hands each input to a `FlowRecorder` when the app starts
with `PARHELION_RECORD_FLOW`, and a tap names its control by accessibility identifier, else label,
else node identifier. `parhelion run --record` sets the variable for the first launch only.

**One replay engine, two runners.** `ViewHost.replay(_:)` plays a flow. `parhelion test` sends it
to an app on the manual clock ([ADR 0012](0012-manual-clock.md)) as a `replay` command, and Swift
Testing calls it in process. Both get a `FlowReport`.

**Checkpoints compare `outline()` without identifiers or frames.** Structure, text, and attributes
are what a flow asserts; frames would fail on every layout tweak. `--update` rewrites them.
A screenshot step can come later through the board comparison.

## Consequences

- Flows are reviewed as diffs and can be written by hand or by an agent. They use the same names
  as the agent tools, so a new `PreviewCommand` works in flows at once.
- The file format is hard to change once flows are committed. A change that breaks old files must
  raise `Flow.currentVersion` and keep reading the old one.
- A flow replays from a fresh app. State that the recording started with, such as a signed-in
  account, is not part of the file.
- Flows name controls, so an app without accessibility identifiers records labels, and two
  controls with one label are recorded by node identifier, which changes when the view structure
  does. Identifiers are the way to make flows durable.
- Under Swift Testing, `Task.sleep` stays on real time. Only `parhelion test` replays on the
  manual clock.
- Text fields are focused, not clicked, in a replay, so the caret starts at the end.
