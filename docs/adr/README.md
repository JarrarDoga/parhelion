# Architecture decision records

Each record describes one design decision that is hard to reverse: the context, the decision,
and its consequences. Records are numbered and never deleted. A decision that is replaced is
marked *Superseded* and links to the record that replaces it.

| Number | Title | Status |
| --- | --- | --- |
| [0001](0001-swiftui-module-shim.md) | Provide a `SwiftUI` module on Linux | Accepted |
| [0002](0002-defer-renderer-backend.md) | Defer the choice of renderer backend | Superseded by 0004 |
| [0003](0003-no-swiftpm-resources.md) | Ship no SwiftPM resources | Accepted |
| [0004](0004-pure-swift-renderer.md) | Draw in pure Swift, show frames in a separate window host | Accepted |
| [0005](0005-model-tree-and-presented-frames.md) | The view tree holds final values; animation affects only what is drawn | Accepted |
| [0006](0006-host-clock-and-shared-frames.md) | The window host owns the frame clock, and frames travel through shared memory | Accepted |
| [0007](0007-phosphor-symbol-images.md) | Draw SF Symbol names with Phosphor Icons, embedded as SVG path data | Accepted |
| [0008](0008-observation-and-main-actor-work.md) | Views observe models with the toolchain's Observation, and the app runs main-actor work while it waits | Accepted |
| [0009](0009-appearance-in-the-tree.md) | The tree records the color scheme and the text size, and preferences take a second pass | Accepted |
| [0010](0010-images-from-the-app-bundle.md) | Images come from the app's raw asset catalog, decoded in pure Swift, through a side table | Accepted |
| [0011](0011-extension-seam.md) | New views, modifiers, MCP tools, and window hooks plug in from their own files | Accepted |
| [0012](0012-manual-clock.md) | A manual clock for agents: `wait` advances the app's time, and replaced executors hold `Task.sleep` | Accepted |
| [0013](0013-recorded-flows.md) | Recorded flows are JSON that the app records and replays | Accepted |
| [0014](0014-mediaplayer-and-avfaudio-shims.md) | Provide `MediaPlayer` and `AVFAudio` modules on Linux | Accepted |
| [0015](0015-gesture-arbitration.md) | Gestures are recognized by the host from the pointer, and arbitrated in one place | Accepted |
| [0016](0016-lazy-windows.md) | Lazy stacks and lists evaluate a window of rows that layout asks for | Accepted |
| [0017](0017-mediaplayer-mpris.md) | `MediaPlayer` reaches the desktop through MPRIS, which the window host owns, over the preview socket | Accepted |

To add a record, copy the structure of an existing one, use the next number, and add it to this
table in the same pull request as the change it describes.
