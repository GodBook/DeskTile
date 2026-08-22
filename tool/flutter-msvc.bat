@echo off
REM Run Flutter with a workaround for this machine's broken Windows SDK registry.
REM
REM Root cause (diagnosed 2026-08-21):
REM   HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots\KitsRoot10   (64-bit view)
REM     = C:\Program Files\Windows Kits\10\      <- has no Include/Lib
REM   HKLM\SOFTWARE\WOW6432Node\...\KitsRoot10   (32-bit view)
REM     = C:\Program Files (x86)\Windows Kits\10\  <- the real SDK
REM CMake drives the 64-bit MSBuild, which reads the 64-bit view, so
REM $(UCRTContentRoot) points at the empty tree and LibraryPath ends up with
REM   C:\Program Files\Windows Kits\10\lib\10.0.26100.0\ucrt\x64
REM Linking then fails with LNK1104: cannot open file 'ucrtd.lib'.
REM
REM Overriding UCRTContentRoot in the environment fixes LibraryPath without
REM touching the registry (verified: link succeeds, ucrt path resolves to the
REM (x86) tree).
REM
REM Usage: tool\flutter-msvc.bat build windows --release
REM        tool\flutter-msvc.bat run -d windows

set "UCRTContentRoot=C:\Program Files (x86)\Windows Kits\10\"
set "PATH=D:\dev\flutter\bin;%PATH%"
set FLUTTER_SUPPRESS_ANALYTICS=true
cd /d "%~dp0.."
flutter %*
exit /b %errorlevel%
