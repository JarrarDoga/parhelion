// Drop-in `SwiftUI` module for platforms without Apple's framework.
//
// Re-exports ParhelionUI so that unmodified sources that say `import SwiftUI`
// compile against Parhelion. See docs/adr/0001-swiftui-module-shim.md.

@_exported import ParhelionUI
