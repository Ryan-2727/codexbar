@echo off
schtasks.exe /Query /TN "CodexQuotaBar Watchdog" >nul 2>&1
if %errorlevel% equ 0 (
    schtasks.exe /Run /TN "CodexQuotaBar Watchdog" >nul 2>&1
    if %errorlevel% equ 0 exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-Existing-CodexQuotaBars.ps1"
wscript.exe "%~dp0Launch-CodexQuotaBar.vbs"
