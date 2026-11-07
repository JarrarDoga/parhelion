# 0018: Audio interruptions and route changes reach the app as a private notification

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Rustle pauses on an interruption (a call, Siri) and when headphones come out. On a phone, iOS
posts `AVAudioSession.interruptionNotification` and `routeChangeNotification`; on Linux nothing
does, so the handlers could not be tested. The `AVFAudio` target
([ADR 0014](0014-mediaplayer-and-avfaudio-shims.md)) exists only on Linux, and `ParhelionUI`,
which runs the app's commands, builds everywhere and cannot depend on it. The MCP tool runs in
the `parhelion` process; the notification must be posted in the app's process.

## Decision

- The tools `audio_interruption` and `audio_route_change` send two `PreviewCommand` cases to the
  app. The app runs them through `ViewHost.postAudioInterruptionBegan(reason:)`,
  `postAudioInterruptionEnded(shouldResume:)`, and `postAudioRouteChange(reason:device:)`, which
  post one private notification, `ParhelionAudioSessionEvent`, with plain string and bool values,
  and then update the host so the screen shows what the handlers changed.
- `AVFAudio` observes that notification. It posts Apple's notification with the object
  `AVAudioSession.sharedInstance()` and Apple's user-info keys and value types (`UInt` raw
  values, and an `AVAudioSessionRouteDescription` for the previous route), and changes the session
  as iOS does: an interruption that begins deactivates it, and a route change moves
  `currentRoute` between the speaker and the device.
- The observer starts the first time the app asks for `sharedInstance()` or reads one of the
  session's notification names, so an app that observes before it asks for the session is served.
  An app that never imports `AVFAudio` sees nothing, as on a phone.
- Reasons and devices travel as case names, so the wire format does not depend on `AVFAudio`'s
  enums. A test posts every name and checks the shim understands it.

## Consequences

- The names and keys of the private notification are duplicated in `ParhelionUI` and `AVFAudio`;
  a test in `SourceCompatibilityTests` fails if they drift.
- The notification is posted synchronously on the thread that handles the command, which is the
  main thread, so a handler that is `@MainActor` runs before the command's reply.
- An app built before this change does not decode the new commands; the tools then report that
  the app did not answer. They are not gated on a capability.
- Not covered: `silenceSecondaryAudioHintNotification`, media services lost or reset, and
  `isOtherAudioPlaying`.
