# Strict Foreground Visibility Design

## Goal

Show Codex Quota Bar only while the official ChatGPT/Codex desktop window is the active foreground application. The desktop window does not need to be maximized.

## Cause

The current foreground detector accepts any window whose title contains `Codex`. A browser tab, File Explorer window, terminal, or other application with `Codex` in its title can therefore be mistaken for the desktop app. The existing overlay-focus exception can then keep the topmost bar visible while the user interacts with it.

## Design

Replace title-based recognition with strict process identity:

- Accept a foreground window when its process is a known Codex process or its executable belongs to the `OpenAI.Codex_` Windows package.
- Do not use window-title text as an identity fallback.
- Do not require the desktop window to be maximized.
- Continue hiding the bar when the desktop window is minimized.

Preserve bar interaction with a narrow exception:

- When the bar itself temporarily becomes the foreground window, keep it visible only if the last recognized ChatGPT/Codex window still exists, is visible, is not minimized, and still passes strict process identity.
- When any other application is the foreground window, clear the remembered desktop handle and hide the bar on the next 250 ms timer tick.

## Scope

Only foreground-window detection and the related README wording will change. Quota retrieval, lifecycle autostart, position, layout, animations, colors, reset times, and synchronization behavior remain unchanged.

## Verification

- PowerShell parses the script and `-ValidateOnly` succeeds.
- The official ChatGPT/Codex window shows the bar whether maximized or restored.
- A non-Codex foreground window hides the bar within 250 ms.
- A non-Codex window whose title contains `Codex` does not show the bar.
- Clicking the bar still opens and closes the details panel without flicker.
- Returning ChatGPT/Codex to the foreground shows the bar again.
- The installed runtime script matches the repository source.
