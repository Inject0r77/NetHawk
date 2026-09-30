@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\NetHawk.ps1" -Action Run -Profile "ALT11"
if errorlevel 1 pause
