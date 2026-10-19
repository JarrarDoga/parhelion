# Architecture decision records

Each record describes one design decision that is hard to reverse: the context, the decision,
and its consequences. Records are numbered and never deleted. A decision that is replaced is
marked *Superseded* and links to the record that replaces it.

| Number | Title | Status |
| --- | --- | --- |
| [0001](0001-swiftui-module-shim.md) | Provide a `SwiftUI` module on Linux | Accepted |
| [0002](0002-defer-renderer-backend.md) | Defer the choice of renderer backend | Proposed |
| [0003](0003-no-swiftpm-resources.md) | Ship no SwiftPM resources | Accepted |

To add a record, copy the structure of an existing one, use the next number, and add it to this
table in the same pull request as the change it describes.
