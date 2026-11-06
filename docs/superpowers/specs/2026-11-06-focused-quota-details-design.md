# Focused Quota Details Design

## Goal

Move the quota bar 40 pixels to the right from its compact-bar baseline and simplify the expanded panel so it focuses on the current five-hour and weekly remaining quotas and their next reset times.

## Compact bar position

- Preserve the current size and styling.
- Position the whole overlay 40 pixels to the right from the original compact-bar baseline. This includes an additional 20-pixel move from the current implementation.
- Keep foreground-only Codex visibility behavior unchanged.

## Quota status colors

Use fixed remaining-quota bands for both the five-hour and weekly windows:

- 40% through 100% remaining: green `#65D5A4`.
- 20% through 39% remaining: yellow `#F2BA55`.
- 0% through 19% remaining: red `#F36D6D`.
- Unavailable quota data: keep the existing neutral gray state.

Apply the selected status color consistently to the compact percentage, status dot, progress line, and expanded percentage.

## Expanded panel

Use two vertically stacked quota sections because the overlay is only 160 pixels wide.

Each section contains:

- A short window label: `5 小时` or `每周`.
- The current remaining percentage in the existing quota status color.
- A prominent `下次重置` label and the complete reset time.

Use closely balanced typography for the two primary values:

- Show the remaining percentage at 18 pixels.
- Show the reset time at 16 pixels.
- Keep both values semibold, with the remaining percentage only slightly larger.

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

## Motion

Use short, non-scaling transitions so text remains sharp:

- Opening the details panel fades it from transparent to opaque while translating it upward by 6 pixels over 180 milliseconds.
- Closing fades the panel out while translating it downward by 6 pixels over 120 milliseconds, then collapses it.
- Use ease-out motion when opening and ease-in motion when closing.
- Clicking the refresh icon rotates the arrow 360 degrees over 400 milliseconds.
- Disable repeat refresh clicks during the arrow animation and quota refresh, then restore the button afterward.
- Start the existing synchronous quota refresh after the single rotation completes; do not add background runspaces or change the data-fetching architecture.

## Data and behavior

- Continue using the same read-only Codex JSON-RPC data source.
- Keep automatic refresh and watchdog behavior unchanged.
- When data is unavailable, continue showing the existing unavailable/waiting messages in the quota and reset fields.
- Clicking the compact bar continues to expand and collapse the details panel.
- Clicking the refresh icon starts the rotation feedback, then requests fresh quota data and updates the sync timestamp.

## Verification

- WPF validation completes successfully.
- The running bar has exactly one watchdog and one UI process.
- Live RPC returns both five-hour and weekly quota windows.
- The installed runtime script matches the repository script.
- Boundary checks confirm 19% is red, 20% and 39% are yellow, and 40% is green.
- Animation checks confirm the details panel uses the specified open and close durations, the close animation collapses the panel when complete, and the refresh icon has a centered rotation transform.
- Static checks confirm the removed heading and status badge are absent, both quota sections and reset fields remain, detail percentages use 18-pixel text, reset times use 16-pixel text, the compact refresh control and last-sync text remain, and the horizontal offset is 71 pixels.
