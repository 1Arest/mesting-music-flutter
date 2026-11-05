@echo off
setlocal
cd /d "%~dp0"
if defined FLUTTER_ROOT (
  call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release --target-platform android-arm64 --no-pub %*
) else (
  call flutter build apk --release --target-platform android-arm64 --no-pub %*
)
exit /b %ERRORLEVEL%
