param([string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (!$JavaHome) { throw 'Set JAVA_HOME or pass -JavaHome for JDK 17 or newer.' }
$taskOutput = Join-Path $taskRoot '.codex-artifacts/2026-10-27-music-refinements/native-host-tests'
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskSource = Join-Path $taskRoot 'third_party/just_audio/package/android/src/main/java/com/ryanheise/just_audio/MestingAudioOutput.java'
$taskTests = @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'test/native_audio_output') -Recurse -Filter '*.java' -File | ForEach-Object FullName)
& (Join-Path $JavaHome 'bin/javac.exe') '-encoding' 'UTF-8' '--release' '17' '-d' $taskOutput $taskSource @taskTests
if ($LASTEXITCODE -ne 0) { throw 'Native registry host compilation failed.' }
& (Join-Path $JavaHome 'bin/java.exe') '-cp' $taskOutput 'MestingAudioOutputHostTest'
if ($LASTEXITCODE -ne 0) { throw 'Native registry host tests failed.' }
