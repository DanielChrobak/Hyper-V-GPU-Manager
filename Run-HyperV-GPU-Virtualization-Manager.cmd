@echo off
setlocal

set "SCRIPT=%~dp0HyperV-GPU-Virtualization-Manager.ps1"
if not exist "%SCRIPT%" (
    echo [ERROR] Missing script: %SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Script exited with code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
