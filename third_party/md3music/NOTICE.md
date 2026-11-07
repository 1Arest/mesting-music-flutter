# md3Music provenance

- Upstream: https://github.com/zzyoxml/md3Music
- Pinned commit: a69503b84e8829f888684f67c163be03c589c014 (rust-local-force)
- Upstream author: zzyoxml and contributors; original notices are preserved.
- License: GNU Affero General Public License, version 3; see LICENSE.
- `rust/` contains the corresponding upstream server sources, Cargo.lock,
  vendored tiny_http sources, tests and build scripts. Beta.11 locally patches
  `rust/src/modules/misc.rs` to retain registered device signing context for SMS
  instead of clearing KUGOU_API_MID/dfid, and adds a corresponding unit test.
- `android/app/src/beta/jniLibs/*/libkugou_server.so` are the upstream binaries
  originally copied from this commit. Beta.11 rebuilds arm64-v8a, armeabi-v7a
  and x86_64 from the patched source with locked dependencies and NDK 28.2;
  see tool/build_md3_beta_native.ps1 and the Beta.11 native-build evidence.
  No binary is placed in main.
- Mesting's `lib/features/music_platform/` is an integration adapter for the
  upstream C ABI and API contracts. It preserves Mesting's UI, Riverpod state,
  database and audio handler rather than importing upstream UI dependencies.
- Beta.17 ports the same pinned commit's `kugou_provider.dart` daily-membership
  flows, `sign_in_calendar_page.dart`/`vip_status.dart` data contracts, and
  `verify_captcha_dialog.dart` challenge handling into isolated Riverpod
  controllers, repositories and Mesting/Cupertino views. The original
  `assets/web/verify_captcha.html` is retained, with WebView supplied by the
  Flutter team. Account ownership and confirmed-success checks remain explicit.
- The integrated derivative is distributed under AGPL-3.0; original third-party
  dependency licenses and copyright notices remain applicable.
- UPSTREAM_DISCLAIMER.md is kept verbatim for review. Its GPLv3/noncommercial
  wording differs from LICENSE and must be resolved before public release.

Do not distribute credentials or signing keystores with source archives.
