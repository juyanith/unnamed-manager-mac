# UnnamedManager

A native macOS keyboard manager in SwiftUI, grown out of Unnamed Launcher:
leader keys and direct bindings for apps, files, commands, shortcuts and
(from M11) windows. A menu bar app with no Dock icon. Its only data is the JSON config file
`~/.config/unnamed-manager/config.json` (no database, no server). What it
does and how: `docs/BRIEF.md`, `docs/SPEC.md`, `docs/STORIES.md`,
`docs/GLOSSARY.md` (use its words in the UI).

## Layout

- `Sources/UnnamedManager/` the app. `App.swift` has the menu bar item, the Bindings window, Settings, and the app delegate. `docs/DESIGN.md` is the design plan.
- `Sources/UnnamedManagerKit/` rules and data logic with no SwiftUI. Tests in `Tests/UnnamedManagerKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds and signs `build/UnnamedManager.app` in the repo (ignored by git). It doesn't install anything; the copy in /Applications comes from Homebrew.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `.github/workflows/` CI (build, unit tests, self-test on every push) and releases (push a `v*` tag). `build.sh --out DIR` and `APP_VERSION` exist for them.
- `docs/` the brief, the spec, the stories, the glossary, and research.
- `ARCHITECTURE.md` targets, threads (the event tap has its own), and seams.

## Build and check

- Build: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/UnnamedManager/test-build`.
- The config format is shared with the Windows app. Its contract lives in `spec/`, a git submodule of the `unnamed-manager` repo (`git submodule update --init` after cloning): `spec/CONFIG-SPEC.md`, `spec/config.schema.json`, `spec/GLOSSARY.md`. `SpecFixtureTests` runs every fixture in `spec/fixtures/manifest.json`. Change the format in the spec repo first, tag it, then move the submodule and make the tests pass. Never edit files inside `spec/` from here.
- Self-test (the app's real functions against a /tmp config): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/UnnamedManager-shots/<page>-light.png` and `-dark.png` for every Bindings page, plus `settings-light.png` and `-dark.png`, then quits. `APP_SNAPSHOT_PAGES=bindings,settings tools/snap.sh` limits the pages.
  For the Guide, the menu bar menu, a sheet, or a popover, add a capture to `Snapshot.swift`.
- Snapshots and the self-test refuse to run without `APP_STORE` (a config file in /tmp).
- Never test against the real config file in `~/.config/unnamed-manager/`.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/UnnamedManager-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Design rules: `design/DESIGN-SYSTEM.md`. Use its tokens; never raw colors, radii, or durations.

- Use Apple's controls and system styles. The accent follows the Mac (`UI/Theme.swift`, `ThemeStore.defaultID = "system"`, no picker).
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- The Bindings window is a sidebar window (`ContentView.swift`) with the pages in `SidebarItem`. Settings (`SettingsView.swift`) is one grouped Form, 520 pt wide; preferences go there, your data goes in the Bindings window.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
