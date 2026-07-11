@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-Existing-CodexQuotaBars.ps1"
wscript.exe "%~dp0Launch-CodexQuotaBar.vbs"
