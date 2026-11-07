# Official media adapter attribution

The Spade authorization-envelope and MP4 CENC AES-CTR media handling in
`android/app/src/main/kotlin/com/mesting/mesting_music/QishuiOfficialAudioDecrypt.kt`
is derived from **myMusic**'s `SodaDecrypt.kt` at commit
`9c0f1f0ccb1b1046306f61c50998e327c040a6bc`, itself attributed there to
`music-lib/soda/crypto.go` and `libresoda/src/soda/crypto.rs`.

Source: https://github.com/mytv-android/myMusic/blob/9c0f1f0ccb1b1046306f61c50998e327c040a6bc/app/src/main/java/com/mytv/mymusic/data/native/SodaDecrypt.kt

License: GNU Affero General Public License v3.0 (see the preserved `LICENSE`).
Mesting changes add strict box/table limits, complete-file checks, exact sample
coverage, cancellation, unknown-scheme rejection and a private-cache bridge.
This is attributed adaptation, not an original cryptographic implementation.

Media request signing and rights are separate: this code consumes only the
authorization supplied for the current official account/request. It does not
create keys, grant rights, or implement a third-party signing server. Temporary
playback cache files are not user download permission.
