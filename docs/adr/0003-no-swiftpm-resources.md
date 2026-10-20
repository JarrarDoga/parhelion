# 0003: Ship no SwiftPM resources

- **Status:** Accepted
- **Date:** 2026-10-19

## Context

Text layout needs font metrics, and the first implementation loaded them from a TrueType file
declared as a SwiftPM resource of `ParhelionUI`.

Apps depend on Parhelion only on Linux (see [ADR 0001](0001-swiftui-module-shim.md)). On
2026-10-19 we built such an app for iOS with xtool 1.22.2. The compile succeeded, but packaging
failed:

```text
Error: ... "The file doesn't exist." ... .build/out/Products/Debug-iphoneos/Parhelion_ParhelionUI.bundle
```

xtool copies the resource bundle of every target in the app's package graph, including targets
that a platform condition excludes from the iOS build. SwiftPM did not build that bundle for iOS,
so packaging failed. Any resource in a target reachable from the `SwiftUI` product breaks iOS
builds of every app that depends on Parhelion.

## Decision

No Parhelion target declares SwiftPM `resources:`. Data that would be a resource is generated
into Swift source and committed. The font metrics come from `Fonts/Inter-Regular.ttf` through
`Scripts/generate-font-metrics.swift`.

CI enforces both parts: it fails if `Package.swift` contains `resources:`, and it fails if the
committed metrics differ from a fresh run of the generator.

## Consequences

- Apps that depend on Parhelion build for iOS with xtool. We verified this after the change: the
  iOS binary links Apple's `SwiftUI.framework` and contains no Parhelion symbols.
- Generated sources add size to the repository: the metrics file is about 35 KB.
- The renderer will need the font file itself, not only metrics. It must load
  `Fonts/Inter-Regular.ttf` without SwiftPM resources, for example by embedding the bytes in
  generated source or by locating the file at run time. The renderer ADR will decide.
- If xtool stops packaging bundles of excluded targets, we can revisit this decision. Reporting
  the behavior to xtool is worthwhile either way.
