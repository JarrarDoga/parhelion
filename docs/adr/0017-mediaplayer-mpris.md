# 0017: `MediaPlayer` reaches the desktop through MPRIS, which the window host owns

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Rustle's now-playing and remote command code calls Apple's `MediaPlayer`
([ADR 0014](0014-mediaplayer-and-avfaudio-shims.md) made it compile on Linux). In a preview it
should be visible and controllable from the desktop: the KDE media widget and `playerctl` speak
MPRIS, a D-Bus interface on the session bus.

## Decision

- **The window host owns the D-Bus connection.** The app sends its now-playing state over the
  preview socket, and the host publishes the MPRIS player. Apps link no D-Bus library, and the root
  package gains no system dependency.
- **The protocol gets one capability, two messages.** `PreviewCapability.mediaSession`,
  `AppMessage.nowPlaying(PreviewNowPlaying)` (wire kind 10, JSON), and
  `HostMessage.remoteCommand(PreviewRemoteCommand)`. Hosts that did not welcome the capability
  never see the message, as for every capability.
- **A bridge joins the shim and the session.** `MediaSessionBridge` (in `ParhelionPreview`) holds
  the last state and the command receiver, so `MediaPlayer` links `ParhelionPreview` and not
  `ParhelionUI`, and the session links neither the shim nor the other way round. The root
  `Package.swift` gains one dependency, on the `MediaPlayer` target, which exists on Linux only.
- **D-Bus is written in Swift.** `ParhelionTooling` has a small client (`DBus.swift`): the
  authentication handshake, the wire format for the types MPRIS uses, and method calls and
  signals. A system library (libdbus, sd-bus, or GIO) would add a package dependency for every
  user of the tool and a package to CI; about 600 lines of Swift, tested against `dbus-daemon`,
  do not. `MPRIS.swift` has the player.
- **The player appears with the first state.** An app that never sets `nowPlayingInfo` never
  touches the bus, and without a session bus the host logs the reason with `PARHELION_DEBUG=1`
  and carries on. The bus name is `org.mpris.MediaPlayer2.parhelion.instance<pid>`, as the spec
  suggests for several instances.
- **Windowless hosts do not offer it.** `parhelion test` and `parhelion mcp` without frames offer
  no capability, so tests and agents on a build machine do not publish to a desktop.

## Consequences

- The host computes `Position` from the elapsed time the app last set and the time since, at the
  playback rate, because MPRIS clients poll it. A jump of more than a second also sends `Seeked`.
- `PreviewChannel` takes a lock around each send, because the app thread that sets
  `nowPlayingInfo` is not the session's loop.
- A relative `Seek` needs the position, so the shim estimates it the same way. A seek reaches
  `changePlaybackPositionCommand` when the app enabled it, and the skip commands otherwise.
- Not done: artwork (`mpris:artUrl` needs a file or URL, and the artwork handler returns a
  `UIImage`, which does not exist here), volume, loop and shuffle, and the lock-screen card in the
  device chrome. `Set` on a writable property is accepted and ignored.
- The D-Bus client reads little-endian messages without file descriptor passing, which is all the
  bus sends to a client that did not ask for more.
