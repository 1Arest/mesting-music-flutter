param([switch]$BuildExample)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
  flutter analyze --no-pub lib test example/lib
  if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed' }
  flutter test --no-pub --concurrency=2
  if ($LASTEXITCODE -ne 0) { throw 'SDK regression failed' }
  if ($BuildExample) {
    Push-Location example
    try {
      flutter pub get
      if ($LASTEXITCODE -ne 0) { throw 'Example dependency resolution failed' }
      & .\package.cmd
      if ($LASTEXITCODE -ne 0) { throw 'Example Android build failed' }
    } finally { Pop-Location }
  }
} finally { Pop-Location }
