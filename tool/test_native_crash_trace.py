"""Run the pure Kotlin trace-reader checks with the project's cached compiler.

No Android device, credentials, SDK installation or Gradle dependency mutation.
Set JAVA_HOME and GRADLE_USER_HOME as for the documented Android build.
"""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
cache = Path(os.environ['GRADLE_USER_HOME']) / 'caches/modules-2/files-2.1'
out = root / '.codex-artifacts/native-crash-trace-tests'
out.mkdir(parents=True, exist_ok=True)

def jar(group, module, preferred=None):
    candidates = sorted((cache/group/module).glob('**/*.jar'))
    if preferred:
        pinned = [p for p in candidates if preferred in p.parts]
        if pinned:
            candidates = pinned
    if not candidates:
        raise FileNotFoundError(f'Missing cached compiler dependency: {group}/{module}')
    return candidates[-1]

stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20')
annotations = jar('org.jetbrains', 'annotations')
compiler = [
    jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'),
    stdlib, annotations,
    jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.2.20'),
    jar('org.jetbrains.kotlin', 'kotlin-reflect'),
    jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm'),
    jar('org.jetbrains.intellij.deps', 'trove4j'),
]
java = str(Path(os.environ['JAVA_HOME'])/'bin/java.exe')
subprocess.run([
    java, '-cp', os.pathsep.join(map(str, compiler)),
    'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect',
    '-jvm-target', '17', '-classpath', os.pathsep.join(map(str, [stdlib, annotations])),
    '-d', str(out/'classes'),
    str(root/'android/app/src/main/kotlin/com/mesting/mesting_music/NativeCrashTrace.kt'),
    str(root/'android/app/src/main/kotlin/com/mesting/mesting_music/VulkanCrashSignature.kt'),
    str(root/'tool/NativeCrashTraceTest.kt'),
    str(root/'tool/VulkanCrashSignatureTest.kt'),
], check=True, cwd=root)
subprocess.run([
    java, '-cp', os.pathsep.join(map(str, [out/'classes', stdlib])),
    'com.mesting.music.VulkanCrashSignatureTestKt',
], check=True, cwd=root)
subprocess.run([
    java, '-cp', os.pathsep.join(map(str, [out/'classes', stdlib])),
    'com.mesting.music.NativeCrashTraceTestKt',
], check=True, cwd=root)
