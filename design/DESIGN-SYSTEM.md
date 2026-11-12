# Unnamed Manager design system

Which token to use, and when. The tokens are in `Sources/UnnamedManager/UI/`. Apple's look stays: only what the system has nothing for gets a token. Read [docs/DESIGN.md](../docs/DESIGN.md) for the surfaces these tokens are used on.

## Theme.swift: accent
- **The app follows the Mac's accent** (`ThemeStore.defaultID = "system"`), and there's no picker. `APP_ACCENT=<id>` is only for comparing snapshots.
- **Read the accent through `.tint`, `Palette.accent`, `Palette.accentText` or `Palette.onAccent`.** Never hard-code a hex.
- **The Guide uses the accent once**, on the outline that flashes for an unbound key. Everything else in the Guide is `.primary` or `.secondary`.
- **A custom color needs four values:** light, dark and both high-contrast versions, via `Color(light:dark:highContrastLight:highContrastDark:)`.
- **Never copy or redefine a semantic color.**

## Grid.swift: spacing
- **Spacing comes from `Space`, on a 4 pt grid.** Margins are `Space.margin` (20), related items `Space.sm` (8), and groups `Space.xl` (20).
- **The Guide** has `Space.margin` padding and `Space.sm` between rows. The keycap is `Space.sm` from its title.

## Radius.swift: corners
- **`Radius.guide` (26):** the Guide and any floating glass panel.
- **`Radius.xs` (6):** keycaps and chips. It's concentric inside the Guide (26 − 20 = 6).
- **`Radius.sm` (8):** custom controls. **`Radius.row` (10):** row hover and selection fills. **`Radius.md` (12):** cards and the error banner.
- **Standard controls keep their system radii.** Never set `cornerRadius:` on a system control.
- **Inner corners are always concentric:** inner = outer − inset. Use `ConcentricRectangle` for a part that can appear both nested and alone.

## Layout.swift: sizes
- **Window sizes** use `Layout.windowMin` and `Layout.windowDefault`, the sidebar uses `Layout.sidebarMin` and `Layout.sidebarIdeal`, and Settings uses `Layout.settingsWidth` (520).
- **The Guide** has `Layout.guideRowsPerColumn` (12) rows per column, up to `Layout.guideMaxColumns` (3) columns of `Layout.guideColumnWidth`. Titles beyond the column width truncate at the end, and VoiceOver reads the full title.
- **Keycaps** are at least `Layout.keycapMinWidth` (28) wide, so a column of keys lines up.

## Surfaces.swift: surfaces and states
- **Glass:** the Guide uses regular Liquid Glass (`.glassEffect(.regular, in: .rect(cornerRadius: Radius.guide))`). With Reduce Transparency it uses `.regularMaterial`. Never put glass on glass, and never use glass in the Bindings window or Settings, where the system's own chrome already has it.
- **Keycaps** use `Surfaces.keycap` as the fill and `Surfaces.keycapStroke` as the outline. Both are a little translucent, so they take on the glass behind them.
- **`Surfaces.warning`** is the one warning color, for a missing permission, a config error or a failed action. Always pair it with a symbol or words.
- **Unavailable rows** (Choose by App with no match) use `Surfaces.unavailableOpacity` plus the words "not available in <App>".
- **Menu bar icon:** the app icon's glyph, two keycaps and ›, drawn as a template image `StatusIcon.glyphSize` square (`MenuBarIcon.image(for:)`). When Enabled is off, draw it at `StatusIcon.offOpacity`. When something needs attention, add the badge, `StatusIcon.badgeDiameter` wide, at the top trailing corner. If the app icon's shapes change, change the glyph with them. Each state also goes in the status item's accessibility label.

## Motion.swift: animation
- **Every animation goes through `Motion`.** Pass `@Environment(\.accessibilityReduceMotion)`, and every token returns nil when Reduce Motion is on.
- **The Guide** fades in with `Motion.guideAppear` and out with `Motion.guideDismiss` (both 120 ms). It never scales or slides.
- **A menu change inside the Guide is instant.** Typing speed matters more than motion. Never animate the Guide's first layout.
- **An unbound key** uses `Motion.errorFlash`, held for `Motion.errorFlashHold`. A failed action's message stays for `Motion.errorMessageHold`, then the Guide closes.
- **In the Bindings window,** rows added, moved or removed use `Motion.listChange`, and custom hover fills use `Motion.hover`. Hover never moves the selection.

## Still to add
- **`Components.swift`:** the `Keycap` view and the key recorder style, with S-005 and S-025. `.textEntry("Label")` on every Form text field people type words into: it left-aligns the text so a typed space shows at once. Number fields stay right-aligned. Style controls with `ButtonStyle` and `ToggleStyle`; never rebuild a control from shapes.

## Check
This should find nothing outside `UI/`:

```bash
grep -rnE 'cornerRadius: [0-9]{1,2}\b|duration: [0-9]|\.spring\(response|\.snappy\b|\.easeInOut|\.easeOut\(|Color\(hex:|Color\(red:' Sources/ | grep -v '/UI/'
```
