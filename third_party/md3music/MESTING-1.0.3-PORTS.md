# Mesting Music 1.0.3 feature ports

Reference: zzyoxml/md3Music v6.1.0, commit
`4f783a998d7a108685dfa2e3dc9449df9c474c4e`, under the existing AGPL license.
The bundled Rust API remains pinned to its existing revision; the routes used
here already exist in that source and embedded server.

- Profile fields and dirty-only writes: `lib/modules/user/profile_edit_page.dart`,
  `lib/services/kugou_api/kugou_api_client.dart` (`/user/update`, `/user/update/avatar`).
- Dynamic Android EQ bands, five frequency zones and nine curves:
  `lib/core/services/equalizer_service.dart`; background initialization and the
  four-second constructor deadline from Android `EqualizerPlugin.kt`.
  Mesting uses its engine lifetime and generation tickets, one existing music
  audio session, atomic apply/rollback and a separate persistence controller.
- Free effect catalogue parsing and effect-to-EQ mapping:
  `lib/modules/sound/sounds_page.dart`; `/get/model`, `/effects/brand`,
  `/effects/brand/detail`, `/effects/match`, `/effects/artist`.
  No IRS/VPF convolution or Viper master-processing engine is claimed.
- MV metadata/quality/URL contracts: `lib/data/models/mv_models.dart`,
  `kugou_api_client.dart`, `/kmr/audio/mv`, `/video/detail`, `/video/url`.
  Media HTTP domain exceptions follow upstream's bounded media-domain policy.
- Sleep timer task semantics: countdown or natural track completion, pause the
  existing owner. Mesting keeps Android and credentials alive as requested.

New and changed pages inherit Mesting's existing Cupertino/Apple glass system;
upstream Material layouts are not copied. Original authorship/license remain
available in Settings and in the corresponding source distribution.
