@echo off
setlocal
set "SCRIPT=%~dp0RTXVideoTuner.ps1"

where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
    start "RTX Video Tuner" pwsh.exe -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SCRIPT%"
) else (
    start "RTX Video Tuner" powershell.exe -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SCRIPT%"
)
exit /b
