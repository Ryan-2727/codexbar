# Focused Quota Details Design

## Goal

Move the quota bar 20 pixels to the right and simplify the expanded panel so it focuses on the current five-hour and weekly remaining quotas and their next reset times.

## Compact bar position

- Preserve the current size and styling.
- Move the whole overlay 20 pixels to the right from its current position.
- Keep foreground-only Codex visibility behavior unchanged.

## Expanded panel

Use two vertically stacked quota sections because the overlay is only 160 pixels wide.

Each section contains:

- A short window label: `5 小时` or `每周`.
- The current remaining percentage in the existing quota status color.
- A prominent `下次重置` label and the complete reset time.

Reset time format remains `M月d日 HH:mm`, without a year or seconds.

Remove these expanded-panel elements:

- `Codex 配额` heading.
- Sync status badge.

Retain the divider between the two sections and the existing expand/collapse animation.

Add a lightweight footer below the quota sections:

- Show `上次同步 HH:mm:ss` on the left.
- When the latest refresh failed, use the same line to indicate that the displayed data may be stale.
- Place a small icon-only refresh button on the right.
- Give the refresh button a hover tooltip so its purpose remains clear without a text label.
- Keep the footer visually secondary to the quota values and reset times.

## Data and behavior

- Continue using the same read-only Codex JSON-RPC data source.
- Keep automatic refresh and watchdog behavior unchanged.
- When data is unavailable, continue showing the existing unavailable/waiting messages in the quota and reset fields.
- Clicking the compact bar continues to expand and collapse the details panel.
- Clicking the refresh icon immediately requests fresh quota data and updates the sync timestamp.

## Verification

- WPF validation completes successfully.
- The running bar has exactly one watchdog and one UI process.
- Live RPC returns both five-hour and weekly quota windows.
- The installed runtime script matches the repository script.
- Static checks confirm the removed heading and status badge are absent, both quota sections and reset fields remain, the compact refresh control and last-sync text remain, and the horizontal offset increased by exactly 20 pixels.
