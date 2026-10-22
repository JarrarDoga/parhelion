# 0006: The window host owns the frame clock, and frames travel through shared memory

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

The preview window stuttered even when the app rendered a frame in 2 ms. Measured on a 12-core
desktop with the Tasks example, a navigation push showed frames 14 to 19 ms apart in a release
build and 9 to 23 ms apart in a debug build:

- The app paced itself with a 60 Hz timer whose timeout was truncated to whole milliseconds,
  and sampled animation time when it woke instead of when the frame would be on screen.
- The window host presented each frame as soon as it arrived, with vsync off. On the owner's
  240 Hz and 180 Hz monitors, frames 16 ms apart stayed on screen for 3, 4, or 5 refreshes in an
  uneven pattern, which reads as judder.
- Each 5.4 MB frame was copied through the socket, which with the channel's buffering cost about
  3 ms per frame, more than drawing it.

Apple's apps pace with `CADisplayLink`, which wakes the app once per refresh and gives it the
`targetTimestamp` at which the frame it draws will be composited. SDL3 has no presentation
timestamps; the only cadence source is a present that blocks until the display refreshes.

## Decision

**The host owns the clock.** The window host enables vsync and reads the display's refresh rate,
again when the window moves to another display. After each present, which returns at the
refresh, it sends the app a `tick` with a target time: the present time plus a whole number of
refresh periods. The app moves its `ViewHost` clock to the target and draws once. The host waits
for that frame until shortly before the next refresh, uploads it, and presents again; a late
frame is shown at the next refresh and the previous one stays up meanwhile. One tick is
outstanding at a time. An app that cannot answer within a refresh is shown for a fixed number of
refreshes per frame, chosen from its slowest recent answers. When vsync is refused, or presents
return without waiting, the host waits for each refresh itself with a precise timer on a grid of
whole periods. When nothing animates, both sides block and use no CPU.

Times on the wire are nanoseconds of `CLOCK_MONOTONIC`, which every process on the machine
shares, so the host's target time means the same moment to the app.

**Frames travel through shared memory.** The app creates an anonymous file (`memfd_create`, or a
POSIX shared memory object that is unlinked at once), divides it into three frame-sized slots,
and passes its descriptor to the host once, with `SCM_RIGHTS` over the existing socket. Each
frame is then a 38-byte message naming a slot, the size, the damaged rectangle, whether the app is
still animating, and the tick it answers. The host uploads straight from the slot and sends the
slot back. If no slot is free, or shared memory cannot be created, the frame goes inline in the
message.

**Both are negotiated.** The app lists capabilities (`hostClock`, `sharedFrames`) in its hello,
which older hosts ignore. A host that supports them answers with a `welcome`, and only then sends
ticks and slot releases or expects slot frames. An older app never receives a message it does
not know, and a newer app talking to an older host keeps sending plain frames and paces itself
with its own timer, now on a fixed 60 Hz grid without truncation. A welcomed app also falls back
to its own timer if ticks stop for 100 ms.

## Consequences

- A push animation in a release build presents every refresh, one period apart. With the
  framework built optimized (see `parhelion run`), debug builds do too.
- Moving a frame costs a copy into the slot, about 0.2 to 0.4 ms, instead of about 3 ms. Drawing
  directly into a slot would remove that copy but needs the renderer to draw into memory it does
  not own.
- The protocol has state: a host must answer each slot frame with a release, and must keep at
  most one tick outstanding, or the app runs out of slots or falls back to its own timer. Hosts
  without a window (`parhelion mcp` without `--window`) offer no capabilities and get the
  original protocol.
- The preview depends on Linux-specific system calls (`memfd_create`, `SCM_RIGHTS`); a macOS
  host would use the POSIX shared memory fallback or a Mach equivalent.
- The wire format gained four message kinds. Changing tick or slot semantics later requires a
  new capability name, so that old and new peers keep agreeing.
