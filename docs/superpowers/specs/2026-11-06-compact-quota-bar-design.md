# Compact quota bar

## Goal

Remove the `Codex 配额` brand text from the compact bar and shorten the bar while preserving readability, the existing soft-glass appearance, and all quota interactions.

## Compact layout

- Remove the compact-only brand text and its adjacent divider.
- Keep the five-hour and weekly quota stacks at equal `44px` widths.
- Reduce the outer width from `248px` to `160px`.
- Reduce horizontal padding from `14px` to `10px`; retain the existing vertical padding.
- Reduce the gap around the remaining center divider from `12px` to `10px`.
- Keep the status dots, labels, percentages, hairline meters, colors, corner radius, hover state, shadow, and typography unchanged.

## Position and expanded details

- Preserve the compact bar's current left edge while its right edge moves inward.
- Keep the `Codex 配额` title inside the expanded details panel for context.
- Keep the five-hour and weekly details, reset times, refresh button, and click behavior unchanged.

## Verification

- Run PowerShell parser validation and the existing WPF `-ValidateOnly` check.
- Confirm the compact source contains no brand element and uses the new width, padding, and gap values.
- Sync the script to the runtime directory and restart through the watchdog launcher.
- Confirm one watchdog process and one bar process are running.
- Confirm the visible compact window measures `160px` wide when Codex is foreground.
- Confirm the expanded details title and both quota sections still exist.

## Scope

Only compact-bar layout and the anchoring constant change. Quota data, synchronization, expanded content, foreground-only visibility, autostart, and watchdog behavior remain unchanged.
