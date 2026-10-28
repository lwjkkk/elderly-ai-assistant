@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_phone_test.ps1"
if errorlevel 1 (
    echo.
    echo Phone test startup failed. Review the message above.
    pause
)
