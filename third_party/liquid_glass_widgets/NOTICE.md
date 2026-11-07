# Liquid Glass Widgets Apple Music example

The Beta.6 bottom navigation, search/accessory composition, glass settings and
play-pill pattern adapt the official Apple Music example by Sebastian Degenaar:
https://github.com/sdegenaar/liquid_glass_widgets/blob/main/example/lib/apple_music/apple_music_demo.dart

Copyright (c) 2024–2026 Sebastian Degenaar. MIT License; see LICENSE.
The fetched reference snapshot and its SHA-256 are retained beside this notice.
The reference `.dart.txt` is documentation and is not compiled into the app.

The runtime dependency is based on liquid_glass_widgets 1.15.0. Beta.12 vendors
the MIT source under package/ with a reproducible correction to the dark
constant perimeter in lightweight_glass.frag; see MESTING_PATCHES.md. Its real
GlassScaffold, GlassTabBar.searchable, bottomAccessory, GlassButton.custom and
interaction physics are used directly. Chinese navigation, Mesting theme tint,
account/search contracts and live playback actions are application adaptations.
No Apple assets, branding or subscription claims are imported.
