# Pinned Flutter Release engine for confirmed Adreno recovery

Mesting 1.0.23 keeps Flutter 3.41.9 / Dart 3.11.5. Upstream's
`FlutterMain::SelectedRenderingAPI` ignores `--impeller-backend=opengles` in
Release even when the embedding supplies the argument before creating an
engine. The first code44 candidate exposed this difference on the real device:
the application requested OpenGLES, while the engine selected Vulkan. That
candidate is not accepted as the crash fix.

The user explicitly selected a custom **Release** engine to retain the full
glass material. `release-opengles.patch` moves only the existing OpenGLES
selection out of the Debug/Profile guard. Default selection, Vulkan selection,
Impeller shader code, Dart VM mode and application material parameters are not
changed. The app supplies the argument only after its narrowly matched crash
history, or in its isolated profile benchmark. This is a workaround for a
confirmed driver path; it does not repair Qualcomm's closed source driver.

Pinned upstream framework commit:
`00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` (tag `3.41.9`), engine artifact
revision `42d3d75a56efe1a2e9902f52dc8006099c45d937`. Dependencies are the exact
revisions in that checkout's `DEPS`. Never apply the patch to another engine
revision without reviewing and rebuilding both ARM variants.

Upstream source and build documentation:

- <https://github.com/flutter/flutter/blob/3.41.9/engine/src/flutter/shell/platform/android/flutter_main.cc>
- <https://github.com/flutter/flutter/blob/3.41.9/docs/engine/contributing/Setting-up-the-Engine-development-environment.md>
- <https://github.com/flutter/flutter/blob/3.41.9/docs/engine/contributing/Compiling-the-engine.md>

Rebuild on Linux with Chromium depot_tools in PATH and the standard Flutter
engine dependencies synchronized. The project helper verifies the source
commit, applies exactly this patch, runs the selector checks, and compiles
optimized Android Release libraries. It works in a separate cache checkout,
leaving the user's ordinary Flutter SDK untouched:

```sh
bash tool/build_flutter_engine_release.sh /absolute/path/to/pinned/flutter
```

Use a Linux filesystem for the checkout and build directory when working in
WSL. The helper keeps vpython environments beside that checkout and invokes
the pinned Ninja binary from DEPS. `MESTING_ENGINE_JOBS=3` reduces concurrency
for a shared 16GiB Windows/8GiB Linux host without changing generated code.

The helper retains compiler optimization and the Release Dart VM/AOT, strips
symbols, and disables the final full LTO link step to fit an 8GiB Linux host.
Omitting LTO can affect binary size and performance; these libraries must be
measured on the phone and are not claimed byte/performance equivalent to the
official engine. It does not enable debugging or service extensions.

The resulting libraries and their build manifest are accepted only after APK
and real-device engine-log verification. A successful compile alone does not
prove runtime selection, glass fidelity or long-term stability. Consult the
1.0.23 validation report for the actual result.

The source delivery includes the verified native-only jars, the exact engine
dependency inventory, hashes, Build IDs and complete native license payload in
`android-release/`. An ordinary application rebuild consumes that bundle and
keeps the SDK's Java embedding. To export a newly compiled engine, use a fresh
output directory (the exporter refuses to overwrite an existing bundle):

```sh
python3 tool/export_flutter_engine_release.py /absolute/path/to/pinned/flutter /absolute/path/to/new-bundle
```

Review the new manifest and replace the source bundle deliberately before the
next application build. Gradle verifies the patch, SDK engine revision, jar
hashes and license payload before packaging a Beta Release APK.

Flutter's BSD license applies to the patch's source context and the engine.
All upstream third-party licenses must accompany any redistributed binary.
