// Drop-in `SwiftUI` module for platforms without Apple's framework.
//
// Re-exports ParhelionUI so that unmodified sources that say `import SwiftUI`
// compile against Parhelion. See docs/adr/0001-swiftui-module-shim.md.
//
// It also re-exports the toolchain's Observation module, as Apple's SwiftUI
// does, so that `import SwiftUI` alone makes `@Observable` available.

@_exported import Observation
@_exported import ParhelionUI
