# Five-hour quota display

## Goal

Restore the Codex five-hour allowance alongside the existing weekly allowance without changing the foreground-only visibility, autostart, watchdog, or synchronization behavior.

## Data mapping

- Read `account/rateLimits/read` from the local Codex app-server.
- Identify the five-hour window by `windowDurationMins = 300` and the weekly window by `windowDurationMins = 10080`.
- Use `primary` and `secondary` only as compatibility fallbacks when duration metadata is missing.
- Convert `usedPercent` to remaining percentage with the existing clamped `100 - usedPercent` calculation.
- Keep the most recent valid snapshot if a refresh fails.

## Compact bar

- Display `5 小时` and `每周` side by side with equal visual width.
- Give each allowance its own status dot, remaining percentage, and hairline progress meter.
- Use the existing thresholds independently for each allowance: green at 20% or more, amber below 20%, and red below 10%.
- Expand the outer width only enough to fit the second allowance while preserving the current soft-glass appearance and taskbar position.

## Expanded details

- Keep the existing header, sync state, last-sync text, and full-width refresh button.
- Show two stacked quota sections: five-hour first, weekly second.
- Each section shows the remaining percentage and reset time formatted as `M月d日 HH:mm`, without a year.
- If one window is unavailable, show that window as unavailable while continuing to display the other valid window.

## Verification

- Confirm the current RPC response maps the 300-minute window to five-hour and the 10080-minute window to weekly.
- Run PowerShell parser validation and the existing `-ValidateOnly` WPF check.
- Run `-CheckRpc` and verify both remaining percentages and reset timestamps are returned.
- Restart the watchdog/runtime copy and confirm one watchdog process, one bar process, and a visible bar window while Codex is foreground.
- Confirm switching away from Codex still hides the bar.

## Scope

Only the quota data model and quota UI are changed. Autostart, watchdog behavior, foreground detection, positioning, and repository documentation remain unchanged unless a later request explicitly asks for them.
