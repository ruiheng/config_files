@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
where pwsh >nul 2>nul
if not errorlevel 1 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%adwf.ps1" %*
    exit /b !ERRORLEVEL!
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%adwf.ps1" %*
exit /b !ERRORLEVEL!
