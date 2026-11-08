# Hidden Watchdog Launcher Design

## Goal

Prevent the long-running quota-bar watchdog from opening a visible Windows Terminal window while preserving all existing lifecycle and recovery behavior.

## Cause

The scheduled task currently launches `powershell.exe` directly in the interactive user session. Windows Terminal is configured as the default terminal host, so it creates a visible terminal window even though PowerShell receives `-WindowStyle Hidden`. The watchdog stays alive by design, which keeps that terminal window open.

## Design

Use the existing `Launch-CodexQuotaBar.vbs` script as the scheduled-task action.

- `Install-Autostart.ps1` will register `wscript.exe` as the action executable.
- The action will pass the quoted path to `Launch-CodexQuotaBar.vbs`.
- The VBS launcher will start `CodexQuotaBar-Watchdog.ps1` through `WScript.Shell.Run` with window style `0` and wait for it to exit. Keeping the VBS process alive ensures Task Scheduler continues to treat the watchdog task as running and ignores overlapping health triggers.
- The logon trigger, one-minute health trigger, single-instance policy, restart settings, and limited interactive user principal remain unchanged.
- `Start-CodexQuotaBar.cmd` already uses the same VBS launcher as its fallback and needs no behavioral change.

This is preferred over `conhost.exe --headless` because it avoids an additional Windows-version dependency, and over a compiled launcher because no new build artifact is required.

## Scope

Only the scheduled-task launch path and the relevant README instructions will change. Quota retrieval, foreground-window detection, layout, animations, refresh behavior, and ChatGPT/Codex lifecycle detection remain unchanged.

## Installation

After updating the source files:

1. Copy the changed launcher and installer files to the installed runtime directory.
2. Run `Install-Autostart.ps1` again to replace the existing task.
3. Leave the task installed and running.

## Verification

- PowerShell parses the installer and watchdog scripts without errors.
- The task action is `wscript.exe` with the installed VBS launcher path.
- Exactly one watchdog and one quota-bar process run while ChatGPT/Codex is open.
- No visible Windows Terminal window is associated with the watchdog.
- Stopping the quota bar causes the watchdog to recreate it within the two-second polling interval.
- Stopping the watchdog causes the one-minute health trigger to recreate it without showing a terminal window or creating duplicates.
- The installed runtime files match the repository sources.
