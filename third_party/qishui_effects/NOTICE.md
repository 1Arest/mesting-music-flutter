# Soda audio-effect artifacts

The three ARM64 binaries are unmodified members of the official Android
21.5.0 sample. PROVENANCE.json records their exact identity. They remain
proprietary artifacts; no open-source or redistribution licence is inferred.
The default effect graphs are extracted from the same sample; runtime/server
configuration and account entitlements can replace or restrict these defaults.
Mesting's adapter and PCM conversion are separate, newly written source.
No DRM keys, installation IDs, account tokens or entitlement modifications
are provided here. ARM32 support of the existing application is preserved;
the Soda official DSP is unavailable on ARM32.

These binaries also require a 4 KiB page process. They are packaged as inert
assets, outside Android's JNI library directories, and extracted into the
app-private code cache only for an explicit, entitled ARM64/4 KiB selection.
Their SHA-256 hashes are checked before loading. This does not make these
original binaries compatible with a 16 KiB page process; selection is refused
there while the existing music engine remains in use. Native output has not
been verified on a physical device.
