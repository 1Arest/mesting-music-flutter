#!/usr/bin/env bash
# Rebuild only the pinned engine in a separate, already synchronized checkout.
# Android engine cross-compilation requires Linux/macOS; it is not a Windows
# Flutter SDK mutation. Keep the final build manifest with redistributed libs.
set -euo pipefail
if test "$#" -ne 1; then
  printf 'Usage: bash tool/build_flutter_engine_release.sh /absolute/pinned/flutter\n' >&2
  exit 2
fi
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
engine=$(cd "$1" && pwd)
expected=00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
test "$(git -C "$engine" rev-parse HEAD)" = "$expected"
test "$engine" != "$project"
# Keep Python environments on the same native filesystem as the engine.
# A Windows-mounted vpython cache can turn short generator scripts into many
# minutes of metadata I/O. This setting is local to the build process.
tool_cache="${MESTING_ENGINE_TOOL_CACHE:-$engine/../engine-tool-cache}"
mkdir -p "$tool_cache"
export VPYTHON_VIRTUALENV_ROOT="$tool_cache/vpython"
export XDG_CACHE_HOME="$tool_cache/xdg"
patch="$project/third_party/flutter_engine/release-opengles.patch"
cd "$engine"
if git apply --check "$patch" 2>/dev/null; then
  git apply "$patch"
else
  # An identical previous application is safe; any other drift stops the build.
  git apply --reverse --check "$patch"
fi
python3 "$project/tool/check_flutter_engine_selector.py" \
  "$engine/engine/src/flutter/shell/platform/android/flutter_main.cc"
# Record the actual synchronized source/CIPD revisions with the binary bundle.
mkdir -p "$engine/engine/src/out"
gclient revinfo --actual --output-json="$engine/engine/src/out/engine-dependencies.json" >/dev/null
cd "$engine/engine/src"
for cpu in arm64 arm; do
  # Preserve optimized Release and AOT. Full LTO linking exceeds a modest 8GiB
  # host; compile with the Release optimizer and omit that final link-time
  # optimization step. This changes size/performance tradeoffs, not VM mode.
  python3 flutter/tools/gn --android --android-cpu "$cpu" \
    --runtime-mode release --no-rbe --no-enable-unittests \
    --no-build-embedder-examples --no-full-dart-sdk --stripped --no-lto \
    --gn-args='symbol_level=0'
  suffix=''
  if test "$cpu" = arm64; then suffix='_arm64'; fi
  "$engine/third_party/ninja/ninja" -j "${MESTING_ENGINE_JOBS:-4}" \
    -C "out/android_release$suffix" lib.stripped/libflutter.so
done
