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

To add a record, copy the structure of an existing one, use the next number, and add it to this
table in the same pull request as the change it describes.
