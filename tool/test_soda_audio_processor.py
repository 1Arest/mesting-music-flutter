"""Run production Java against the real cached Media3 AAR, without a device.

Only Android platform access/native DSP and Util's platform initialization are
seams. AudioProcessor, EMPTY_BUFFER, AudioFormat and BaseAudioProcessor are the
actual release classes. --source permits proving a retained old source fails.
"""
from pathlib import Path
import argparse
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'third_party/just_audio/package/android/src/main/java/com/ryanheise/just_audio/SodaAudioProcessor.java')
parser.add_argument('--jdk', type=Path, default=Path('D:/CodexCache/android-build/jdk/jdk-17.0.20.1+1'))
parser.add_argument('--media3-cache', type=Path, default=Path('D:/CodexCache/android-build/gradle/caches/modules-2/files-2.1/androidx.media3/media3-common/1.9.2'))
parser.add_argument('--output', type=Path, default=root / '.codex-artifacts/native-soda-audio')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
aars = list(args.media3_cache.rglob('*.aar'))
assert len(aars) == 1, 'Provide the pinned Media3 1.9.2 cache directory'
jar = args.output / 'media3-common-1.9.2.jar'
with zipfile.ZipFile(aars[0]) as aar:
    jar.write_bytes(aar.read('classes.jar'))
sources = [str(args.source), *map(str, (root / 'test/native_soda_audio').rglob('*.java'))]
subprocess.run([str(args.jdk / 'bin/javac.exe'), '-encoding', 'UTF-8', '--release', '17', '-cp', str(jar), '-d', str(args.output), *sources], check=True)
guava = sorted((args.media3_cache.parents[2] / 'com.google.guava/guava').rglob('guava-33.4.8-android.jar'))
assert len(guava) == 1, 'Provide the pinned cached Guava runtime required by Media3'
subprocess.run([str(args.jdk / 'bin/java.exe'), '-cp', ';'.join(map(str, [args.output, jar, guava[0]])), 'SodaAudioProcessorHostTest'], check=True)
