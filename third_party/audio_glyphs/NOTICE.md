# Audio destination glyph

The earlier outline used `device-airpods.svg` from [Tabler Icons](https://github.com/tabler/tabler-icons/blob/main/icons/outline/device-airpods.svg), under its included MIT licence. That attribution and licence remain for the historical implementation.

Following the user's explicit request for the original AirPods Pro shape, the private 2026-11-02 UI candidate uses the pinned `airpodspro.svg` paths from Compose Cupertino's SF symbol export. The source URL, commit and SHA256 are in `airpodspro.provenance.json`; the upstream source header and `LICENSE-COMPOSE-CUPERTINO.txt` are retained. `airpods_pro_glyph.dart` converts the two paths without reshaping or changing their aspect ratio. The independently drawn intermediate approximation was rejected and removed.

The original symbol remains subject to Apple's [SF Symbols](https://developer.apple.com/sf-symbols/) terms; the upstream project's Apache source-code header is not a claim that it grants separate Apple symbol rights. This work prepares a local candidate, not a public distribution approval. No Apple font is bundled. The glyph represents the output device visually; native metadata retains the actual headset name.
