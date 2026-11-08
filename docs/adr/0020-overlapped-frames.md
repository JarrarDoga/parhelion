# 0020: The window host overlaps the app's drawing of a frame with showing the one before

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

[ADR 0006](0006-host-clock-and-shared-frames.md) has the host send a tick after each present and
wait for its answer until shortly before the next refresh. Everything that makes a frame then
runs one after another in each refresh: the tick crosses the socket, the app moves its clock and
draws, the frame crosses back, and the host uploads it, about 1 ms for an iPhone 18 Pro Max frame
at 2×, and presents it. At 120 Hz a refresh is 8.3 ms, so the app had about 6.5 ms to answer.

Rustle's Collection and Now Playing screens take the app 7 to 8 ms a frame at 2× on the 6-core
machine the fixtures were measured on (#67), after the caches of ADR 0019. With one step after
another, the host showed them every second refresh, or as soon as each frame arrived, about every
10 ms, off the display's grid. iOS has the same pipeline and overlaps it: the app commits a frame
while the render server draws the one before, so an app has about a whole refresh to draw.

## Decision

**The host sends the next tick as soon as an answer arrives**, before it uploads and presents
that answer, so the app draws the next frame while the host shows this one. Each answer is shown
at the refresh it was drawn for, on the grid of the last present, or at the first refresh after
its upload when it is late. The next tick's target is that refresh plus the refreshes each frame
is shown for. It goes out no earlier than one refresh before the answer it follows is shown, so
the app is never more than two frames ahead of the screen. One tick is still outstanding at a
time, and the app is idle when a tick arrives.

**The refreshes each frame is shown for follow the app's throughput.** They are the fewest that
hold both rules over the last 16 answers: on average a frame takes no more than them and an eighth
of a refresh, which the one refresh the app draws ahead absorbs, and all but the 3 slowest answers
arrive within them and one more refresh, less the upload. A frame slower than that, as when new rows scroll into view, misses its refresh and is
shown at the next, and the frames after it are shown every refresh again; before, one slow frame
made the next 16 frames each wait for two refreshes.

**The answer ends the host's wait as it arrives.** The host waits for it on the connection's
condition and reads the window's events every millisecond, instead of waiting on the window's
event queue, which SDL wakes about a millisecond late. With the app drawing the next frame
meanwhile, that millisecond came out of every frame.

## Consequences

- A frame reaches the screen up to one refresh later after the input it shows: 8.3 ms at 120 Hz.
  The preview's input already waits for the next tick to be drawn, so a tap or drag is drawn one
  or two refreshes after it arrives instead of one.
- An app that takes 7 to 8 ms a frame at 120 Hz is shown at every refresh. An unoptimized app
  with 12 ms frames on a 240 Hz display is shown every third refresh instead of every fourth.
- The app's drawing and the host's upload run at the same time, so they share the machine's cores.
- A present that waited for a slow frame no longer resets the count of presents that returned
  early, so the host still finds that vsync is not real, as with `SDL_VIDEODRIVER=offscreen`,
  within a few frames.
- `measure-frames.py` counts the same `present at` lines as before. Late frames now land on the
  next refresh rather than whenever they arrive, so its gaps are whole refreshes.
