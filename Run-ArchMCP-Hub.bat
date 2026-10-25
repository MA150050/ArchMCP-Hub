@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Setup-And-Run.ps1"
if errorlevel 1 (
  echo.
  echo ArchMCP Hub could not start. Review the message above.
  pause
)
