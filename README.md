# Codex Quota Bar

A lightweight Windows desktop bar that shows Codex five-hour and weekly remaining quota, with clear warning states and a compact details panel.

![Codex Quota Bar soft-glass preview](assets/codex-quota-bar-example.svg)

## Highlights

- Reads live quota and reset times from the local Codex CLI read-only `app-server` JSON-RPC.
- Appears only while a Codex desktop window is in the foreground; hides when another app becomes active.
- Soft-glass dark UI with low-contrast borders, hover polish, status dots, and compact progress lines.
- Click the bar to expand a details panel with reset times, sync state, and a manual sync button.
- Uses green, amber, and red states for healthy, low, and critical remaining quota.
- Cleans up older bar instances before launch to prevent duplicates.
- Optional Windows sign-in autostart.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1.
- The official Codex CLI installed and authenticated.

If PowerShell blocks the `codex` shim, use the `.cmd` entry point:

```powershell
codex.cmd login
codex.cmd login status
```

Install the CLI if needed:

```powershell
npm.cmd install -g @openai/codex
```

## Start

Double-click `Start-CodexQuotaBar.cmd`, or run:

```powershell
.\Start-CodexQuotaBar.cmd
```

The launcher stops older instances and starts the bar without a console window.

## Optional sign-in autostart

Install:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1
```

Remove:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1 -Remove
```

## Verify the quota connection

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexQuotaBar.ps1 -CheckRpc
```

## Privacy and security

- Starts only `codex -s read-only -a untrusted app-server`.
- Does not read browser cookies or store passwords, OAuth tokens, or API keys.
- Does not call private web quota endpoints; the authenticated local Codex CLI manages credentials.

## Files

| File | Purpose |
| --- | --- |
| `CodexQuotaBar.ps1` | WPF overlay, foreground detection, RPC sync, and interactions |
| `Start-CodexQuotaBar.cmd` | Cleans old instances and launches the bar |
| `Stop-Existing-CodexQuotaBars.ps1` | Stops duplicate bar processes |
| `Launch-CodexQuotaBar.vbs` | Starts PowerShell without a console window |
| `Install-Autostart.ps1` | Adds or removes Windows sign-in autostart |
| `assets/codex-quota-bar-example.svg` | README example image |

## Troubleshooting

If `-CheckRpc` reports that Codex is not authenticated, run `codex.cmd login` and finish browser authorization.

If the bar is not visible, open the Codex desktop window and run `Start-CodexQuotaBar.cmd` again.
