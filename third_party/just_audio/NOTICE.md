# Local just_audio routing adapter

Based on the unmodified pub.dev `just_audio` 0.10.6 package by Ryan Heise (MIT; see `package/LICENSE`). Kept Dart, Android and Darwin sources plus upstream metadata. No example, cache, build output or test fixtures are vendored.

Local additions are deliberately bounded:

- The optional `androidAudioOutputOwner` constructor argument binds one logical music owner to each lazily created native player. Ordinary just_audio callers and other platforms retain the upstream path.
- The Android audio sink delegates track creation to Media3's default provider, and exposes that actual track to `MestingAudioOutput`. The bridge uses public `AudioTrack.setPreferredDevice`, `getRoutedDevice` and routing callbacks, and informs the same existing ExoPlayer via `setPreferredAudioDevice` so its sink/capability state follows the choice. It creates no player, uses no hidden API and does not change global Bluetooth or communication mode.
- Media3 1.9.2 is explicitly pinned. This was already this application's resolved version through `video_player_android` 2.9.5; the patch makes the existing runtime contract explicit.

Output preference is process-local, survives source changes, and is cleared when the chosen connected output disappears. An accepted request while paused is shown as pending until playback confirms the route. No device acceptance is inferred from host tests.

2026-11-06: SodaAudioProcessor's queueInput treats empty Media3 drain buffers
as a no-op and preserves unread output. This avoids EMPTY_BUFFER self-copy and
does not discard an already buffered DSP tail. The JVM regression uses actual
Media3 1.9.2 processor classes; the Android/native bridge is a host-only seam,
not evidence of physical DSP or playback acceptance.
