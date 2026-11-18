# Green button fills (deferred)

Evaluated 2026-11-18, put off: the green button is rarely clicked, so it's
more effort than it's worth for now. Listed under Later in `STORIES.md`.

The idea: an option to make the green title bar button Fill the window
(as `window.fill` does) instead of entering macOS full screen.

## How vorssaint-utils does it

`../vorssaint-utils/Sources/Vorssaint/Services/WindowMaximizer.swift`.
It's GPL-3.0 and this repo is MIT: read it for behavior and pitfalls, never
copy its code.

- A session event tap for left mouse down and up, installed only while the
  feature is on and Accessibility is granted.
- Mouse down, with no modifier held: a cheap window-server check first
  (`WindowServerTrafficLightHitTest`), because some apps stall when asked
  through Accessibility on every click. Then the Accessibility element at
  the point, its window, and whether the point is in `kAXZoomButton` or
  `kAXFullScreenButton`. It skips windows already in full screen and apps
  on its exception list. On the green button, it swallows the mouse down.
- Mouse up on the same button: toggles between the screen's usable area
  and the frame from before. If that fails, it presses the real zoom button
  through Accessibility, never the full screen button.
- Extras: enhanced user interface off while the window moves, a
  settle-and-retry loop for apps that resize late, a workaround for apps
  that won't go under a Dock at the side, an animation, and a per-app
  exception list.

## What we'd reuse

| Need | Already here |
|---|---|
| Fill math, gap, press again to restore | `WindowControl.run(.fill)` and `FillMemory` (Kit) |
| Setting frames safely | `AXWindowSystem.setFrame` |
| A per-app opt-out | `Config.Windows.AppRules` and the Apps table on the Windows tab |
| A watcher that follows a setting | `QuitOnCloseWatcher.follow()` |
| Permission | Accessibility is enough for a mouse tap |

## Plan

1. Spec v17, in the spec repo first: `windows.greenButtonFills` (boolean,
   default `false`, Mac only) and a `greenButton` rule in `windows.apps`
   (default `true`). On Windows both are `other-platform-field`. Fixtures,
   then tag `spec-v17`.
2. Kit `GreenButton.swift`: a pure decision from the facts (setting,
   modifiers, which button, window in full screen, the app's bundle ids
   with the apps it's inside, its rule): pass through, Fill, or press the
   native button. Unit tests, and decoding, validation and writing for the
   two fields.
3. Move the `.fill` case of `WindowControl.run` into
   `fill(_ window: WindowRef, toggle:)`, so a click and the Fill shortcut
   share `FillMemory` and undo each other. The button always toggles, and
   works on a window that isn't focused (a click on a back window's green
   button doesn't bring it forward).
4. `Windows/GreenButtonWatcher.swift`: its own `CGEvent` tap for the mouse,
   never the key tap, on its own thread as `KeyCapture` does, so a slow
   hit test never delays keystrokes. Check window-server bounds first, then
   Accessibility with a short timeout (0.25 s). Never ask the application
   element for its role, which keeps Chromium apps out of full
   accessibility mode. Swallow the mouse down only on a confirmed green
   button, Fill on mouse up through `WindowControl` on the main thread,
   and press the native zoom button for a window that can't be resized.
   Follows the setting like Quit on Close, turns the tap back on after a
   timeout, owned by `Launcher`.
5. Settings, Windows tab: a "Green Button" section with a toggle such as
   "Green Button Fills the Screen". A footer says that holding a modifier
   while clicking keeps macOS's behavior. A fifth column, "Green Button",
   in the Apps table. A glossary entry; the glossary bans "maximize",
   "zoom" and "full screen" as names for Fill, so the words need care.
   Snapshots and grid checks.
6. A story: [unit] the decision and the fields; [self] two clicks fill and
   restore a fake window that isn't focused, the shortcut and the button
   undo each other, Settings saves and undoes, and the tap stays off in
   snapshots and the self-test; [manual] the risks below.

Suggested: no animation, to match the Fill shortcut; the second click
always restores, whatever an action's `toggle` says. A setting needs no
menu bar item, but confirm that with the CLAUDE.md rule.

Rough size: about 2 hours for the spec and the Kit, half a day for the
watcher, an hour for Settings and snapshots. Testing in real apps is the
biggest part.

## Risks to try by hand

- Holding the mouse down on the green button no longer shows the tiling
  menu, because the mouse down is swallowed. Hovering still shows it, and
  a modifier lets the click through.
- Green buttons that can't be reached: custom title bars (some Electron
  apps) and windows that can't be resized. These pass through or press
  the native button.
- Windows that resize late or snap their size: Terminal's character grid,
  Safari's animation, a Dock at the side.
- A small extra cost on every click while it's on: measure it with the
  `performance` skill.
- A window already in full screen must pass through, so its green button
  still leaves full screen.
- Multiple displays, Stage Manager, Finder.
