# Native interface design

Sparky applies the interface hierarchy and feedback principles in Emil Kowalski's [apple-design](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md) and [emil-design-eng](https://github.com/emilkowalski/skills/blob/main/skills/emil-design-eng/SKILL.md). The references target the web; Sparky implements the relevant ideas in SwiftUI and AppKit without a web UI or an added animation library.

| Before | After | Why |
| --- | --- | --- |
| Large page title and three equally weighted statistics | Compact page header and one schedule summary | Keep the message, schedule and recipients prominent. |
| Repeated large cards | Shared section surfaces and grouped rows | Give related settings a consistent hierarchy. |
| Contact checkbox controls | Full-row selection with a checkmark, press feedback and a selected-only filter | Make targets easier to use and selection explicit beyond color. |
| Send status inferred from general engine activity | Explicit batch-only presentation state | Reading contacts must not show a send cancellation action. |
| One card for every history item | Date groups with disclosure rows | Keep the result visible and the evidence available on demand. |
| Logs always visible in Settings | Account, General and Diagnostics groups | Keep everyday preferences easy to find. |

## Implementation rules

- Use system type styles, native buttons, pickers, switches, sheets and disclosure controls. Keep Sparky orange for selection and the primary action; use semantic result colors with text labels.
- Use a material only for structural chrome. The full-height sidebar uses `NSVisualEffectView` with a behind-window sidebar material at normal effect opacity; controls remain fully opaque. The sidebar becomes solid when the system requests reduced transparency. Surface borders respond to increased contrast.
- All three native window buttons have an 18-point corner inset. Green toggles usable-screen-height zoom and restore while preserving width; fullscreen and fullscreen tiling remain disabled. Sidebar effect opacity is 100% and follows window activation, with no extra transparency multiplier. Content/frame/live-resize constraints share a 940 × 760-point content minimum, matched by the SwiftUI root; the plan’s recipient row stays above the fixed send footer at this size.
- The window has no empty toolbar band. A transparent title bar retains native controls, with reserved space above the sidebar header. The sidebar stays expanded at 225 points with no collapse control or shortcut. Its brand row starts 54 points from the top, with balanced gaps around the 32-point mark. An opaque 1-point gray separator divides the columns, adapting to dark appearance and increased contrast.
- Press feedback is immediate. Only the pointer hover background has a short 120 ms interpolation; reduced motion disables it. Navigation and keyboard selection have no custom transition or stagger.
- Keep the main action in a fixed footer. Empty states use the available content area rather than enlarging the window. Long names truncate without pushing selection controls out of view.
- Preserve the separate send review, input validation and per-account preferences. Visual changes must not alter dispatch or receipt rules.

## Validation

`--window-self-test` exercises contact row hit areas, persisted choices, the selected-only filter, keyboard search, Escape review cancellation, task presentation, Cmd-W, Dock policy and compact empty-state controls. `--self-test` covers account/scan/delivery/scheduling behavior and the batch presentation flag. Preview modes cover light/dark appearance, long names and loading/empty states with synthetic data.

Reduced motion, reduced transparency and increased contrast use SwiftUI's system accessibility environment. Those system preferences are not changed by the tests.
