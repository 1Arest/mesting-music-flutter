# Remote release-note ZIP fixture

`release_notes_apk_fixture.zip` is a synthetic ZIP, not an installable APK or a
third-party download. Its DEFLATE-compressed JSON names future version 99.0.1 /
code 9901 and contains two Chinese fixture notes. A stored 80,000-byte zero-filled
entry makes a tail Range smaller than the complete file, so the test exercises
real ZIP offsets rather than accidentally fetching the entire archive.

The production reader accepts only the notes asset entry, validates its CRC,
declared sizes, local header/name and target version/code, and leaves download
and Android installation to the existing update controller.

The far-future identity deliberately stays outside bundled release history.
