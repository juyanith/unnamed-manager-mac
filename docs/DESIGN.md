# Unnamed Manager: design plan

The mac-design plan for [BRIEF.md](BRIEF.md). It follows Apple's rules (the mac-design skill's design-rules.md, cited below as "rule N"). Words come from [GLOSSARY.md](GLOSSARY.md).

## Feeling

**Quick and out of the way.** The launcher is felt, not seen. A known sequence runs with nothing on screen. When the Guide does appear, it's small and still, shows its rows at once, and is gone the moment the sequence ends. Every surface follows this: no splash screen, no tour, no sounds except the error bell, and no animation longer than a short fade.

## Archetype

A **menu bar extra, the Guide panel, a Settings window, and a Help window** (rule 7, and the menu bar utility archetype). The real entry point is the leader chord. The menu bar menu is for status and control. Settings is for setup, which you rarely do.

| Surface | What it is | Opened by |
| --- | --- | --- |
| Guide | A non-activating, borderless Liquid Glass `NSPanel`. It never becomes key or main, and it shows the path and the next keys. | Pausing during a sequence (S-005, S-016) |
| Menu bar menu | A `MenuBarExtra` with the app icon's glyph (two keycaps and ›) drawn as a template image, and a badge for warnings | Clicking the menu bar icon |
| Settings | A `Settings` scene with toolbar tabs: General, Bindings, Actions, Contexts, Windows (S-085). The title names the tab (settings.md). | Settings… (⌘,) |
| Help | A `Window` scene titled "Unnamed Manager Help", with the Help page (S-052). | Help, Unnamed Manager Help, and a Show Help binding |
| Welcome | A small window shown only on first run (S-040). It isn't a tour: it lists the steps you need to finish setup. | First launch |

**Why one Settings window** (S-085): key bindings are settings, so they're in one place with the rest, as Xcode keeps its Key Bindings and Mail its Rules in Settings. Until S-085 they had a Bindings window of their own, beside a Settings window; that was two windows for setup, and one could open behind the other. Help isn't a setting, so it has its own window, as in other Apple apps, and the Help menu opens it.

**Dock icon:** there is none (`LSUIElement`). While a window is open, the app switches to `.regular` so it gets a main menu with Edit (Undo) and a Window menu. It goes back to `.accessory` when the last window closes (rule 79, menus.md).

## Information architecture

**Settings tabs** (toolbar tabs, each with an SF Symbol, settings.md):

| Tab | Symbol | Content |
| --- | --- | --- |
| General | `gearshape` | A grouped Form, at most 600 pt wide and centered: Guide, Keys, Feedback, Startup (S-032, S-036) |
| Bindings | `keyboard` | An outline of leaders › menus › bindings with Key, Title and Action columns, in file order (S-023 to S-029) |
| Actions | `bolt` | A list of actions plus a form for the selected one, which changes with its type (S-030) |
| Contexts | `macwindow.on.rectangle` | An ordered list of contexts with their apps (S-031) |
| Windows | `rectangle.split.2x1` | A grouped Form, at most 600 pt wide and centered: Windows, Focus and Swap, Apps (S-071, S-082, S-084) |

The window title names the tab ("General", "Bindings"), as in Apple's Settings windows. Settings opens on Bindings, then on the tab you used last. **Every tab has the same size, so switching tabs never resizes the window** (a window that jumps between a narrow form and a wide editor is distracting). You can resize it on any tab; it opens with a 980 × 640 page and keeps the size you give it while the app runs. The Form tabs center their rows at a readable width and scroll when they're taller than the window. The editor tabs (Bindings, Actions, Contexts) put their list on the left and a form for the selection on the right, 280 pt wide on Bindings. There's no inspector.

The toolbar holds the tabs, so a list's add and remove buttons sit in a bar under it (`ListBar`), as in Mail's Rules: New Binding, New Menu and Delete under the outline, New and Delete under Actions and Contexts.

**Help** (S-052): a grouped Form, centered and at most 640 pt wide: your leaders and direct bindings grouped as in Home, the keys that work in every sequence, the built-in actions, the words, and links. Clicking a key shows it on Settings' Bindings tab.

**A note on Theme:** the config's `ui.theme` setting only changes the Guide. Rule 28 advises against an app-wide appearance setting, so the windows always follow the Mac.

## Command map

The status item menu acts as the menu bar while no window is open (menus.md, rule 68). Its key equivalents work only while the menu is open.

| Command | Where | Shortcut |
| --- | --- | --- |
| Status line ("Not capturing leaders") | Menu bar menu, disabled first item, only when Enabled is off | — |
| Needs Permission › Accessibility / Input Monitoring — Open Settings… | Menu bar menu, only when one is missing | — |
| Relaunch to Finish Setup | Menu bar menu, only when needed | — |
| Config Error lines and Open Config File | Menu bar menu, only on error | — |
| Enabled | Menu bar menu, check mark | — |
| Reload Config | Menu bar menu, and the File menu | ⌘R |
| Open Config File / Show in Finder (⌥) | Menu bar menu, and the File menu | — |
| Settings… | Menu bar menu and the app menu | ⌘, |
| Help (menu bar menu) / Unnamed Manager Help (Help menu): open the Help window | Menu bar menu, and the Help menu | None: macOS keeps ⌘? for the Help menu's search. A Show Help binding opens it from anywhere |
| Version line ("Version 0.1.3", or "Version 0.1 (main, aa45720)" for a local build) | Menu bar menu, disabled item above Quit | — |
| Config line ("Config loaded at 14:02", or "Created config file") | Menu bar menu, disabled item under the version line | — |
| Quit Unnamed Manager | Menu bar menu and the app menu | ⌘Q |
| New Binding / New Menu | File menu, the bar under the outline, and the context menu | ⌘N / ⇧⌘N |
| New Action / New Context | The bar under their list | — |
| Record Key | Edit menu, the context menu, and Space on a selected row | ⌘K, Space |
| Sort Alphabetically | Edit menu and the context menu (on a menu) | — |
| Duplicate | Edit menu and the context menu | ⌘D |
| Delete | Edit menu and the context menu | ⌫ |
| Undo / Redo | Edit menu | ⌘Z / ⇧⌘Z |
| General / Bindings / Actions / Contexts / Windows | View menu, to switch tabs (and open Settings) | ⌘1 to ⌘5 |

**Inside a sequence** (the Guide, not menus): Cancel (Escape), Back (Backspace), and the step keys. The Guide's footer teaches Cancel and Back.

The bindings themselves are global shortcuts, so they never appear as menu items.

## Empty states

Each uses `ContentUnavailableView` with the first action as a button (rule 27).

| Where | Title | Message | Button |
| --- | --- | --- | --- |
| Bindings, no config yet (only seen if the starter couldn't be written) | No Bindings | Add a leader such as Hyper+Space, then the keys under it. | New Binding |
| Actions | No Actions | Actions are what bindings do: open an app, run a command, send a shortcut. | New Action |
| Help, no bindings | No Bindings | Add a leader such as Hyper+Space with keys under it, or a direct binding such as Hyper+T. Your keys are listed here. The rest of the page still shows. | New Binding |
| Contexts | No Contexts | A context is a set of apps, such as your browsers, that Context Aware actions check. | New Context |
| Bindings, config invalid | The banner above the outline lists the errors, and the outline shows the last valid config (S-023, S-034). | — | — |

The Guide never has an empty state, because validation forbids empty menus.

## The Guide

Its look and behavior, as the base for design-system tokens and story S-005:
- **Material:** a regular Liquid Glass panel. It counts as all control layer, so its rows sit directly on the glass with no cards or row backgrounds (rule 9). It has no tint, and the only accent color is the outline that flashes for an unbound key.
- **Shape:** a rounded rectangle with radius `Radius.guide` (26). Keycaps nested inside use `Radius.xs` (6), which is concentric with the panel's 20 pt padding (rule 14). Tokens: [design/DESIGN-SYSTEM.md](../design/DESIGN-SYSTEM.md).
- **Layout:**
  - The path row comes first, in Headline style with the › separators in secondary text.
  - Rows show the keycap (a monospaced key name in a small rounded rectangle), then the title in Body style, then a trailing › on menus.
  - A Use Application row shows its app's 24 pt icon between the keycap and the title, and an Open row the Finder icon of its file or folder, or for a URL the icon of the app that opens it (S-054, S-055). A menu shows the menu bar icon's glyph, 16 pt, in secondary color. An entry's own icon wins; an SF Symbol draws in secondary color, centered in the same 24 pt space (S-056). When any row in a column has an icon, every row in it keeps that space, so titles line up; a column with no icons has no icon space.
  - The footer has the Cancel and Back keycaps in Caption style, centered under the rows, below a separator.
  - The content is 20 pt from the panel edge, rows are 8 pt apart, and everything is on the 4 pt grid.
- **Size:** it fits its content. Up to 12 rows make one column, up to 24 make two, and more make three. It is never resizable.
- **Motion:** a 120 ms fade in and out, with no scaling or sliding. With Reduce Motion it appears instantly. A menu change is instant with no transition, because typing speed matters most.
- **Dimming:** none. It's a HUD, so rule 62's dimming exception applies.
- **Reduce Transparency:** glass gives way to the standard `.regularMaterial`.
- **Theme:** `ui.theme` sets the panel's appearance (aqua or darkAqua), or leaves it following the system.

## Review set

Snapshot pages to add as each surface lands:
- `hud`, `hud-error` (S-005, S-015, S-018)
- `menubar`, `menubar-warning` (S-002, S-008, S-009)
- `general`, `bindings`, `actions`, `contexts`, `windows` (Settings' tabs, with `windows-bottom` when the Form scrolls)
- `help` (the Help window)
- `welcome` (S-040)

Every surface is captured as the key window, in light and dark.

## Known gotchas

- **Closing and reopening a SwiftUI `Window` scene crashed AppKit on macOS 26.** It looped on constraints once state changed afterwards. Hide a window instead of closing it (patterns.md, menu bar app section), and test this on 27. Settings and Help close normally on 27; the self-test closes and reopens both.
- **`MenuBarExtra(isInserted:)` hung one launcher at launch.** There's no "hide menu bar icon" setting in version one, so this doesn't apply yet.
