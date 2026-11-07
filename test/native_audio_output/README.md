# Audio output registry host regression

Run `tool/test_music_output_bridge.ps1 -JavaHome <JDK-17-or-newer>` from PowerShell. It compiles the **production** `MestingAudioOutput.java` together with test-only Android/Media3 public-API fakes, then executes lifecycle assertions. Output lives under the ignored `.codex-artifacts` directory. No package is built or installed, no device is contacted, and the Pub cache is unchanged.

This verifies pending versus confirmed choices, lazy-player/track replacement, late disposal, owner isolation, rejected requests, recovery and observer cleanup. It cannot verify an OEM accepts a route, real Bluetooth switching, audible continuity, audio focus or GPU rendering. Those remain device acceptance work.
