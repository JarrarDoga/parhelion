# 0014: Provide `MediaPlayer` and `AVFAudio` modules on Linux

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Rustle, an iPhone music app that previews on Linux through Parhelion, calls Apple's `MediaPlayer`
(now-playing info and remote commands) and `AVFAudio` (`AVAudioSession`). Apple's frameworks do not
exist on Linux, so `import MediaPlayer` fails there, as `import SwiftUI` would without
[ADR 0001](0001-swiftui-module-shim.md).

## Decision

The root package declares targets and products named `MediaPlayer` and `AVFAudio`, only when the
manifest is evaluated on Linux, in the same way as the `SwiftUI` target. Apps depend on them with
`condition: .when(platforms: [.linux])`. On iOS the targets are absent, so `import MediaPlayer` is
Apple's framework.

The first version is compile-only: it holds state and does nothing else. Issues #64 and #79 make
them work (MPRIS on the desktop bus, and audio interruptions).

The root package also declares an empty `ParhelionTesting` target for issue #71. It is on every
platform, because the snapshot tests will not be Linux-only.

## Consequences

- Where Apple's API uses `UIImage` (`MPMediaItemArtwork`) or Objective-C selectors
  (`MPRemoteCommand.addTarget(_:action:)`), the shim takes `Any` or leaves the method out.
- `Scripts/check-ios-build.sh` is the check that these targets do not reach an iOS build.
