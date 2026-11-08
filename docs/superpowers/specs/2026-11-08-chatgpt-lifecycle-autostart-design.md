# ChatGPT Lifecycle Autostart Design

## Goal

Make Codex Quota Bar follow the installed ChatGPT/Codex desktop application's lifecycle reliably:

- Start the bar within a few seconds after the desktop app opens.
- Stop the bar after the desktop app fully closes.
- Recover automatically if the lightweight watchdog exits unexpectedly.

## Architecture

Use one per-user Windows scheduled task named `CodexQuotaBar Watchdog`.

The scheduled task:

- Starts at user logon with limited user privileges.
- Runs the existing watchdog hidden through Windows PowerShell.
- Allows only one watchdog instance.
- Has no execution time limit.
- Restarts the watchdog after one minute when it exits unexpectedly.
- Is started immediately when installed, so a sign-out is not required.

The watchdog remains lightweight and polls every two seconds. The quota bar process itself is not permanent.

## Desktop application detection

Treat the primary `ChatGPT.exe` process from an `OpenAI.Codex_` Windows package as the desktop app.

- Ignore Chromium helper processes whose command line contains `--type=`.
- Start one quota bar process when the primary desktop process appears.
- Stop all quota bar processes when the primary desktop process disappears.
- Recognize both `powershell.exe` and `pwsh.exe` when finding existing bar or watchdog processes.

## Installation and removal

Update `Install-Autostart.ps1` to register the scheduled task and remove the legacy Startup-folder shortcut.

Running the installer normally will:

1. Remove `Codex Quota Bar.lnk` from the Startup folder.
2. Register or replace the scheduled task for the current user.
3. Start the scheduled task immediately.

Running the installer with `-Remove` will:

1. Remove the legacy shortcut if present.
2. Stop and unregister the scheduled task if present.
3. Stop the watchdog and quota bar processes launched from the same installation directory.

## Diagnostics

Write a small `CodexQuotaBar-Watchdog.log` file beside the runtime scripts.

- Log watchdog start and stop, desktop-app state changes, bar start and stop, and caught exceptions.
- Do not log every polling cycle.
- Keep the log bounded by rotating it when it exceeds 256 KB.
- Logging failures must not stop lifecycle monitoring.

## Existing behavior

Keep these behaviors unchanged:

- The bar is visible only while the foreground window belongs to ChatGPT/Codex.
- Quota data, colors, layout, details, animations, and refresh behavior are unchanged.
- `Start-CodexQuotaBar.cmd` remains available for manual recovery.

## Verification

- PowerShell parses the installer and watchdog without errors.
- Installing creates exactly one enabled `CodexQuotaBar Watchdog` scheduled task and removes the legacy shortcut.
- With ChatGPT/Codex already running, starting the task produces exactly one watchdog and one bar process.
- Terminating the bar while the desktop app remains running causes the watchdog to recreate it within the polling interval.
- Live quota RPC returns both five-hour and weekly data.
- The runtime copies match the repository sources.
- Removal behavior is validated without leaving the user's installation removed at the end.
