"""Compile the production PCM meter against pinned Media3 and run host checks."""
from pathlib import Path
import subprocess, zipfile
root = Path(__file__).resolve().parent.parent
out = root.parent / 'native-rhythm'
out.mkdir(exist_ok=True)
cache = Path('D:/CodexCache/android-build/gradle/caches/modules-2/files-2.1')
aar, = (cache / 'androidx.media3/media3-common/1.9.2').rglob('*.aar')
jar = out / 'media3-common.jar'
with zipfile.ZipFile(aar) as archive:
    jar.write_bytes(archive.read('classes.jar'))
guava, = (cache / 'com.google.guava/guava').rglob('guava-33.4.8-android.jar')
jdk = Path('D:/CodexCache/android-build/jdk/jdk-17.0.20.1+1/bin')
sources = [root / 'third_party/just_audio/package/android/src/main/java/com/ryanheise/just_audio/RhythmAudioProcessor.java',
    root / 'third_party/just_audio/package/android/src/main/java/com/ryanheise/just_audio/RhythmSpectrum.java',
    root / 'test/native_rhythm/RhythmAudioProcessorHostTest.java', root / 'test/native_soda_audio/fakes/androidx/media3/common/util/Util.java']
subprocess.run([str(jdk / 'javac.exe'), '-encoding', 'UTF-8', '--release', '17', '-cp', str(jar), '-d', str(out), *map(str, sources)], check=True)
subprocess.run([str(jdk / 'java.exe'), '-cp', ';'.join(map(str, [out, jar, guava])),
    'com.ryanheise.just_audio.RhythmAudioProcessorHostTest'], check=True)
