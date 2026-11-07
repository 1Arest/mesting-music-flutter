"""Export immutable native-only jars from the separately built Release engine.

Keeping the upstream Java embedding avoids changing the plugin ABI. The Gradle
build consumes these two jars only for betaRelease; stable and profile retain
their ordinary engine. Each output is version-bound and hashed before use.
"""
import argparse
import datetime
import hashlib
import json
import re
from pathlib import Path
import struct
import subprocess
import zipfile

PINNED = '00b0c91f06209d9e4a41f71b7a512d6eb3b9c694'
ENGINE_REVISION = '42d3d75a56efe1a2e9902f52dc8006099c45d937'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('engine', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    engine = args.engine.resolve()
    project = Path(__file__).resolve().parent.parent
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=engine, text=True).strip() == PINNED
    changed = subprocess.check_output(['git', 'diff', '--name-only'], cwd=engine, text=True).splitlines()
    assert changed == ['engine/src/flutter/shell/platform/android/flutter_main.cc'], changed
    patch = project / 'third_party/flutter_engine/release-opengles.patch'
    subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=engine, check=True)
    dart = engine / 'engine/src/flutter/third_party/dart'
    dart_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=dart, text=True).strip()
    assert dart_revision == 'c70f78e7d682c158c15ca0c26c729b3ccb932284', dart_revision
    dependency_snapshot = (engine / 'engine/src/out/engine-dependencies.json').read_bytes()
    assert len(json.loads(dependency_snapshot)) > 20
    # Exporting over a previous bundle could silently change a frozen build.
    # A revised engine must go to a fresh directory and receive fresh hashes.
    args.output.mkdir(parents=True, exist_ok=False)
    files = []
    for abi, folder, elf_class in (
        ('arm64-v8a', 'android_release_arm64', 2),
        ('armeabi-v7a', 'android_release', 1),
    ):
        build = engine / 'engine/src/out' / folder
        gn_args = (build / 'args.gn').read_text(encoding='utf-8')
        assert 'flutter_runtime_mode = "release"' in gn_args
        assert 'is_debug = true' not in gn_args
        assert 'enable_lto = false' in gn_args and 'symbol_level = 0' in gn_args
        assert 'stripped_symbols = true' in gn_args
        library = build / 'lib.stripped/libflutter.so'
        assert library.is_file(), f'Build the stripped engine target first: {library}'
        native = library.read_bytes()
        notes = subprocess.check_output([
            str(engine / 'engine/src/flutter/buildtools/linux-x64/clang/bin/llvm-readelf'),
            '-n', str(library)
        ], text=True)
        build_id = re.search(r'Build ID: ([0-9a-f]+)', notes)
        assert build_id, 'Keep the engine Build ID for native crash correlation'
        sections = subprocess.check_output([
            str(engine / 'engine/src/flutter/buildtools/linux-x64/clang/bin/llvm-readelf'),
            '-S', str(library)
        ], text=True)
        assert '.debug_' not in sections and not re.search(r'\.symtab\b', sections)
        assert native[:4] == b'\x7fELF' and native[4] == elf_class
        assert native[5] == 1
        minimum = 16384 if elf_class == 2 else 4096
        if elf_class == 2:
            offset = struct.unpack_from('<Q', native, 32)[0]
            size, count = struct.unpack_from('<HH', native, 54)
        else:
            offset = struct.unpack_from('<I', native, 28)[0]
            size, count = struct.unpack_from('<HH', native, 42)
        segments = []
        for index in range(count):
            pos = offset + index * size
            if struct.unpack_from('<I', native, pos)[0] != 1:
                continue
            align = struct.unpack_from('<Q' if elf_class == 2 else '<I', native, pos + (48 if elf_class == 2 else 28))[0]
            assert align >= minimum, (abi, align)
            segments.append(align)
        assert segments
        target = args.output / f'{abi}-release.jar'
        with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_STORED) as jar:
            item = zipfile.ZipInfo(f'lib/{abi}/libflutter.so', date_time=(2026, 4, 29, 0, 0, 0))
            item.external_attr = 0o644 << 16
            jar.writestr(item, native)
        files.append({'abi': abi, 'jar': target.name, 'jarSha256': sha(target.read_bytes()),
                      'nativeSha256': sha(native), 'nativeBytes': len(native),
                      'nativeBuildId': build_id.group(1),
                      'symbolsStripped': True,
                      'loadSegmentAlignments': segments, 'gnArgsSha256': sha(gn_args.encode())})
    # Upstream checks in the complete native NOTICE for these pinned DEPS.
    # Read the committed bytes so Windows checkout line endings cannot alter
    # the attribution payload or its build manifest hash.
    licenses = subprocess.check_output([
        'git', 'show', 'HEAD:engine/src/flutter/sky/packages/sky_engine/LICENSE'
    ], cwd=engine)
    assert len(licenses) > 1_000_000, 'Complete upstream license payload required'
    asset_dir = args.output / 'assets'
    asset_dir.mkdir()
    (asset_dir / 'LICENSE.flutter-engine.txt').write_bytes(licenses)
    (args.output / 'engine-dependencies.json').write_bytes(dependency_snapshot)
    metadata = {'flutterVersion': '3.41.9', 'frameworkCommit': PINNED,
                'upstreamEngineRevision': ENGINE_REVISION, 'runtimeMode': 'release',
                'dartRevision': dart_revision, 'dependencySnapshotSha256': sha(dependency_snapshot),
                'compilerOptimization': 'release', 'linkTimeOptimization': False,
                'patchSha256': sha(patch.read_bytes()),
                'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'licensesSha256': sha(licenses), 'files': files}
    (args.output / 'engine-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
