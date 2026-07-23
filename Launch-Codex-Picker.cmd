@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-And-Launch-Codex-Picker.ps1"
if errorlevel 1 (
  echo.
  echo Codex Picker failed to start.
  pause
)
endlocal
