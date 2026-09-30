@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\NetHawk.ps1" -Action Run -Profile "FAKE_TLS_AUTO_ALT3"
if errorlevel 1 pause
