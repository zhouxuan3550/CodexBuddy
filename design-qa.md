# CodexUsage v0.3.0 Design QA

- Source visual truth: `/Users/macstudio/.codex/generated_images/019f838d-0edf-7800-a801-89a9761c8dcb/exec-3129d74d-5df9-41fc-bc33-219e6d9e6d8e.png`
- Implementation screenshot: `/tmp/CodexUsage-v0.3-option2-final.png`
- Combined comparison: `/tmp/CodexUsage-v0.3-option2-comparison-final.png`
- Viewport: native macOS menu, 380 pt wide, dark appearance, Simplified Chinese
- State: weekly window, 17% remaining, reset on July 25, live session event, fresh data

## Full-view comparison evidence

The final comparison places the selected recovery-timeline concept and the native implementation at the same rendered height. The implementation preserves the source hierarchy: compact header, weekly usage and remaining value on one row, now-to-reset timeline, relative reset time, contextual low-usage advice, confidence status, then native actions and footer.

## Focused-region comparison evidence

A separate crop was not required because both panels remain fully readable at the full comparison size. The small typography, timeline endpoints, semantic colors, action icons, separators, and keyboard shortcuts are all legible in the combined image.

## Findings

- No actionable P0, P1, or P2 differences remain.
- [P3] The isolated native menu capture appears gray because macOS vibrancy is captured without the desktop backdrop; in normal use it follows the active system material and dark appearance.
- [P3] Action rows use standard `NSMenuItem` density instead of the concept's enlarged custom hover row. This is intentional so keyboard navigation, submenus, shortcuts, and macOS accessibility behavior remain native.
- [P3] The implementation capture includes the real menu-bar title `W 17%` above the panel; this is surrounding product context rather than part of the menu layout.

## Required fidelity surfaces

- Fonts and typography: SF system fonts and monospaced digits match the native target. The percentage is deliberately restrained at 22 pt after user feedback, with no wrapping or clipping.
- Spacing and layout rhythm: header, summary, timeline, advice, confidence line, actions, and footer align to a consistent 20 pt inset. Excess vertical space from the first pass was removed.
- Colors and visual tokens: system red, green, label, secondary-label, and separator colors map directly to semantic macOS tokens and adapt to appearance changes.
- Image quality and asset fidelity: all visible icons are SF Symbols; no placeholder, custom SVG, emoji, or raster approximation is used.
- Copy and content: `17%` consistently means remaining usage. Dates, advice, data source, freshness, actions, About, and Quit text match the selected Simplified Chinese state.

## Comparison history

1. First option-2 pass found two P2 issues: the custom summary view left too much empty space before the action rows, and `刷新中...` remained visible after loading completed.
2. The summary height was reduced from 270 pt to 240 pt. The Combine-driven UI refresh was deferred to the next main-loop turn so it reads the committed `isLoading` value.
3. Copy was aligned with the source: `刷新用量`, `刚刚更新`, and `退出 CodexUsage`. The post-fix comparison shows the stable timeline state with no loading residue and balanced spacing.

## Implementation checklist

- [x] Recovery timeline is the primary visual structure.
- [x] Remaining percentage is compact and semantically colored.
- [x] Reset date and relative time use live data.
- [x] Low/normal/high advice changes with usage state.
- [x] Live/fallback/stale confidence states remain supported.
- [x] Refresh, official Usage, Settings, About, and Quit remain functional native controls.
- [x] Simplified Chinese and English remain supported.

## Follow-up polish

- Consider a dedicated light-appearance comparison in a later release if light mode becomes a product priority.

final result: passed
