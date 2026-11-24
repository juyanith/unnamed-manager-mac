# Unnamed Manager: stories

Built from [BRIEF.md](BRIEF.md), [SPEC.md](SPEC.md), the shared spec in [../spec/CONFIG-SPEC.md](../spec/CONFIG-SPEC.md) and [research/launchers.md](research/launchers.md). M1 to M8 and the stories after `## Dropped` are Unnamed Launcher's, all done. Unnamed Manager's version one is M9 to M11. M12 adds held menus and Recent Windows ([research/held-menus.md](research/held-menus.md)). There is no reference app, so `Screens:` names the snapshot pages that show each story.

**Snapshot pages:**

| Page | Shows |
| --- | --- |
| `hud` | The HUD over a sample app |
| `hud-error` | The HUD after an unbound key or a failed action |
| `hud-home`, `hud-home-wide` | Home in one column, and groups side by side |
| `menubar` | The menu bar menu, all OK |
| `menubar-warning` | The menu bar menu with a missing permission or a config error |
| `welcome` | The first-run window |
| `welcome-import` | The first-run window offering to copy the Unnamed Launcher config |
| `general` | Settings' General tab |
| `bindings` | Settings' Bindings tab (until S-085, the Bindings page of the Bindings window) |
| `actions` | The Actions tab |
| `contexts` | The Contexts tab |
| `windows`, `windows-bottom` | The Windows tab, and its end when it scrolls |
| `help`, `empty-help` | The Help window, with and without bindings |
| `help-builtin` | The Help window's Built-In Actions, with Place Window open |
| `bindings-builtin` | A binding with a built-in action, and its Built In menu |
| `actions-help` | The Actions page with a Show Help action |
| `actions-window` | The Actions page with each window action's form |
| `hud-window` | The Guide on a Windows menu with every window action |
| `settings` | The Settings window, until S-085 split it into General and Windows |
| `hud-held` | The Guide on a held menu, with Cancel and the highlight (S-091) |
| `hud-recent`, `hud-recent-more` | The Guide on Recent Windows, with marks, and on its second page (S-092, S-093) |
| `bindings-hold`, `bindings-list` | A leader with Hold on, and a menu that's a list, in the Bindings tab (S-094) |

**How each acceptance line is checked:** `[snap]` snapshot, `[unit]` unit test, `[self]` self-test, `[manual]` a person must try it.

**Seed data:** snapshot mode loads a fixture config with two leaders, a nested menu, actions of every type, and two contexts. From S-070 it also has a Windows menu with one binding of each window action. Each of these can be created in Settings (S-024 to S-032).

---

## M1 Core loop

Press a leader, step through a menu from the config file, and launch an app. You can use it for a day by editing the JSON by hand.

### S-001 Load and check the config file
As the user, I write `~/.config/unnamed-launcher/config.json` and the app loads it when it launches.
Screens: menubar
Acceptance:
- [unit] Every rule in SPEC.md Validation rejects a config with a message naming the entry or action and the rule. Unused actions and contexts give warnings.
- [unit] A config that has only `version` and one leader with one binding loads, with every setting at its default.
- [unit] Entry order is kept exactly as in the file.
- [self] If no file exists, the app writes a starter config with one leader (Hyper+Space), two example bindings, and a Show Help direct binding (Hyper+H, S-053), then loads it.
UX:
- Flow: launch the app, which reads the config file → if the file is missing, writes the starter config → the menu bar icon shows Ready. There's nothing to undo, and the starter file is never written over an existing file.
- Surface: none of its own. The status appears in the menu bar menu (S-008).
- States: missing file → starter written, and the menu shows "Created config file" once. Invalid file → error state (S-008). Valid → Ready.
- Words: the starter has the leader "Commands" (Hyper+Space) with bindings "Finder" (F, Use Application) and "Terminal" (T, Use Application, `com.apple.Terminal`). Errors name the path and the rule in one sentence, such as "Binding “Hyper+Space Q” uses action “open-foo”, which isn't defined." No codes, no blame.
- Access: n/a.
Status: done

### S-002 Grant the permissions the app needs
As the user, I see which permission is missing in the menu bar menu and click to open the right System Settings pane.
Screens: menubar-warning, menubar
Depends: S-001
Acceptance:
- [snap] With Accessibility or Input Monitoring missing, the menu bar icon shows a warning badge and the menu lists each missing permission with an "Open System Settings…" item.
- [self] With a permission missing, no event tap is installed.
- [manual] After you grant both, keys are captured without relaunching. If macOS requires a relaunch, the menu offers "Relaunch to Finish Setup".
UX:
- Flow: click the menu bar icon (with its warning badge) → the menu lists each missing permission → "Open Accessibility Settings…" opens that pane → you turn the app on and come back → the app re-checks when the menu opens and when it becomes active, the row disappears, and capture starts. Way back: closing System Settings changes nothing.
- Surface: menu bar menu rows (inline: a status the user acts on right where it's shown). There's no alert. A missing permission isn't urgent enough to interrupt, and the welcome window (S-040) comes later.
- States: both missing → two rows. One missing → one row. Both granted → no rows, and the icon is normal. Granted but macOS still blocks it → "Relaunch to Finish Setup".
- Words: a section header "Needs Permission", then rows "Accessibility — Open Settings…" and "Input Monitoring — Open Settings…". Under them, a disabled line in sentence case: "Unnamed Launcher needs both to capture your leader keys."
- Access: the menu is fully keyboard-operable as a standard NSMenu. The warning badge is also announced: the status item's accessibility label is "Unnamed Launcher, needs permission".
Status: done
Verified: no tap without permissions (self-test), menu status model (self-test), and by hand on 2026-11-08: after granting both, the warning dot cleared and Hyper+Space showed the Guide with no relaunch. Not yet checked: the menu snapshot (menus can't be captured without Screen Recording).

### S-003 Start a sequence with a leader chord
As the user, I press Hyper+Space anywhere and the launcher takes over the keyboard until the sequence ends.
Depends: S-001, S-002
Acceptance:
- [unit] When idle, the engine consumes only leader chords. Every other event passes through.
- [unit] Once a sequence starts, every key-down, repeat and matching key-up is consumed.
- [self] The tap callback returns in under 1 ms for 1,000 synthetic events.
- [manual] The app in front never sees the leader. For example, Hyper+Space in a text field types nothing.
Status: done
Verified: engine rules and 1,000 events in under 200 ms (unit tests). Not yet tried by hand: Hyper+Space typing nothing in a text field.

### S-004 Step through menus with single keys
As the user, I press A then T after the leader to reach Applications › Terminal.
Depends: S-003
Acceptance:
- [unit] A child menu's key opens that menu, and a child binding's key ends the sequence with that binding.
- [unit] Leader modifiers that are still held are ignored on step keys. Any other modifier makes the step not match.
- [unit] Keys match by physical position (US ANSI), whatever the active layout.
- [unit] Menus can nest without limit. A test with 6 levels passes.
Status: done

### S-005 See the options in the HUD
As the user, I see a small panel showing where I am and which keys I can press next.
Screens: hud
Depends: S-004
Acceptance:
- [snap] The HUD shows breadcrumbs ("Commands › Applications") and one row per child, in file order: the key in a keycap, the title, and a › on rows that open a menu.
- [snap] Light and dark versions both read clearly over a busy background.
- [manual] The app that was in front stays active, keeps its focus ring and caret, and gets no keys while the HUD is up.
- [self] The HUD panel never becomes the key window.
UX:
- Flow: press the leader → the guide appears (after the delay, S-016) → press a key → the guide updates in the same frame, or closes when a binding runs. Escape cancels and Backspace goes back (S-007).
- Surface: Panel (a tool kept open beside the work that you watch while you type). It's a non-activating, floating, borderless Liquid Glass panel with no title or close button.
- States: normal (path plus rows). Too many rows → two columns after 12 rows; past 24, three columns. Long titles truncate at the end, and the full title is spoken by VoiceOver. A Context Aware binding with no match is dimmed and its row reads "not available in <App>" (S-013). An empty menu can't happen because validation blocks it.
- Words: the path uses the menu titles joined with " › ", starting with the leader's title, for example "Commands › Applications". Each row shows a keycap (key name: "E", "Space", "F5"), the title, and a trailing "›" if it opens a menu. The footer shows the keycaps "esc Cancel" and "delete Back" in secondary text.
- Access: keys come from the event tap, so the guide needs no focus. VoiceOver announces the path when the guide opens and each menu change ("Applications, 3 keys") through an accessibility notification, without moving VoiceOver focus. Keycaps are not color-only. Text is at least 11 pt, and the guide follows Increase Contrast. Reduce Motion turns the appear animation into a fade.
Status: done
Verified: rows, footer, never key (self-test), light snapshot hud-light.png. Not yet checked: dark snapshot and glass (need Screen Recording), focus staying in the app in front (by hand).

### S-006 Open or switch to an app with a binding
As the user, I press Hyper+Space E and Zed comes to the front, launching first if it isn't running.
Depends: S-004
Acceptance:
- [self] When the app is running, it's activated. When it isn't, `NSWorkspace` launches it by `bundleId`.
- [self] When the bundle id isn't installed, the sequence ends and the failure is recorded (shown in S-015).
- [manual] From the leader press to the app activating takes under 100 ms when the app is already running.
Status: done
Verified: missing app reported (self-test). Not yet tried by hand: activation speed under 100 ms.

### S-007 Cancel or go back mid-sequence
As the user, I press Escape to stop, or Backspace to go up one menu.
Depends: S-005
Acceptance:
- [unit] Cancel ends the sequence without running anything, from any depth.
- [unit] Back goes to the parent menu. In a leader's own menu, it opens Home (S-050), or ends the sequence when there's only one top-level entry.
- [snap] After Back, the HUD shows the parent menu's breadcrumbs and rows.
UX:
- Flow: during a sequence, Escape → the guide fades out and nothing runs. Backspace → the guide shows the parent menu, and Backspace in the leader's own menu cancels.
- Surface: the guide (S-005).
- States: when the sequence ends with no visible guide (it was still waiting for its delay), nothing appears. The feedback is simply that the next key types normally.
- Words: the footer keycaps "esc Cancel" and "delete Back" show the configured keys by name. When Back is turned off, the Back keycap is hidden.
- Access: VoiceOver announces "Cancelled" on Cancel and the parent menu's name on Back.
Status: done

### S-008 Reload the config and see its errors
As the user, I choose "Reload Config" or "Open Config File" in the menu bar, and if the file is broken I see why.
Screens: menubar, menubar-warning
Depends: S-001
Acceptance:
- [unit] A reload with errors keeps the last valid config running.
- [snap] With an error, the menu shows the first error with its entry path, and the icon shows a warning badge.
- [self] "Open Config File" opens the file in the default JSON editor.
UX:
- Flow: menu bar icon → "Reload Config" (⌘R in the menu) → valid: the menu closes, and the next open shows "Config loaded at 14:02". Invalid: the icon gets its warning badge, and the menu shows the error with "Open Config File". Way back: the last valid config keeps running, so nothing breaks.
- Surface: menu bar menu rows (inline). Never an alert, because a broken file doesn't stop the app working.
- States: OK → a disabled line "Config loaded at 14:02" under the version line (S-051). Error → a section "Config Error" with the first error in sentence case, wrapped to 2 lines with the full text in a tooltip, plus "+2 more" if there are more. Warnings (unused actions) never show in the menu, only in Settings (S-034) and the log.
- Words: "Reload Config", "Open Config File", "Show in Finder" (with ⌥ held), and "Config Error" as the section header. Errors follow S-001's pattern.
- Access: standard NSMenu. The error line is a disabled item, so VoiceOver reads it in order.
Status: done
Verified: errors keep the last config, status line and warning icon (self-test). Not yet tried by hand: Open Config File and Show Config in Finder.

### S-009 Turn the launcher off and on, or quit
As the user, I uncheck "Enabled" in the menu bar menu so no keys are captured, or choose Quit.
Screens: menubar
Depends: S-003
Acceptance:
- [self] When disabled, the event tap is removed. Turning it back on reinstalls the tap.
- [snap] When disabled, the menu bar icon is dimmed.
- [self] Quit removes the tap before the app exits.
UX:
- Flow: menu bar icon → "Enabled" (a check mark that toggles) → the icon dims and leaders type normally again → choose it again to turn it back on. "Quit Unnamed Launcher" (⌘Q) quits with no confirmation, since nothing is lost.
- Surface: menu bar menu, a toggle item (inline: changes one value).
- States: on → check mark, normal icon. Off → no check mark, dimmed icon, and the status line reads "Not capturing leaders". Enabled is remembered across launches.
- Words: menu order is the status line (only when off), "Enabled", a separator, "Reload Config", "Open Config File", a separator, "Edit Bindings…" (⌘B), "Settings…" (⌘,), "Help", a separator, the version line, the config line, "Quit Unnamed Launcher" (⌘Q).
- Access: the status item's accessibility label includes the state: "Unnamed Launcher, off".
Status: done
Verified: Enabled off removes capture, dims the icon, VoiceOver label (self-test). Not yet tried by hand: the dimmed icon in the menu bar.

## M2 Actions

### S-010 Open a file, folder or URL
As the user, I bind a key to `~/notes` or `https://…` and it opens in its default app.
Depends: S-006
Acceptance:
- [unit] A leading `~` expands to the home folder, and nothing else is expanded.
- [self] File URLs and web URLs both open through `NSWorkspace`.
Status: done

### S-011 Run a command
As the user, I bind a key to `["zed", "~/notes"]` and it runs with no shell.
Depends: S-006
Acceptance:
- [unit] Arguments are passed literally. Only a leading `~` in `command` and `cwd` is expanded.
- [self] `cwd` defaults to the home folder, and `env` is added to the inherited environment.
- [self] A program that can't be found ends the sequence with a failure, and the app doesn't wait for a program that does start.
Status: done
Tried by hand on 2026-11-08: `open -a Calculator`, and `sh -c` with cwd ~/Downloads.

### S-012 Send a shortcut to the app in front
As the user, I bind Hyper+F F to send ⌘F to the app I was using.
Depends: S-006
Acceptance:
- [unit] `send` parses one or more chords, and `Primary` maps to ⌘.
- [self] Sent events carry only the chord's own modifier flags, even while Hyper is still held.
- [manual] ⌘F reaches the app that was in front when the leader was pressed.
Status: done
Verified: chord parsing (unit tests), event flags, key codes and the marker (self-test, events built but not posted). Tried by hand on 2026-11-08: ⌘F reached the app in front.

### S-013 Pick an action by the app in front
As the user, I bind one key that sends ⌘L in a browser and ⌘F everywhere else.
Screens: hud
Depends: S-012
Acceptance:
- [unit] The first context in `contexts` order that matches the front app's bundle id and has a variant wins. Otherwise `fallback` runs, and with no fallback the action is unavailable.
- [snap] In the HUD, a contextual binding that's unavailable for the front app shows as dimmed.
- [unit] Pressing an unavailable binding gives error feedback and runs nothing.
Status: done
Verified: context order, fallback, unavailable stays in the menu (unit tests); dimmed row (self-test, /tmp/UnnamedLauncher-shots/hud-light.png). Tried by hand on 2026-11-08: ⌘L in Safari; dimmed, beeping and staying open in other apps.

### S-014 Reserve a key with a no-op
As the user, I bind a key to `noop` to hold its place or show a note in the HUD.
Depends: S-004
Acceptance:
- [unit] A `noop` binding ends the sequence and does nothing else.
Status: done

### S-015 See why an action failed
As the user, when an app isn't installed or a command can't start, the HUD tells me and the log records it.
Screens: hud-error
Depends: S-006
Acceptance:
- [snap] The HUD shows a red error line, such as "Couldn't open dev.zed.Zed: not installed", for 2 seconds, then closes.
- [self] Every failure is written to the unified log under subsystem `net.unnamed.launcher`.
Status: done
Tried by hand on 2026-11-08: a missing bundle id showed the warning for two seconds.
Verified: shown, closes after 2 s, logged (self-test); /tmp/UnnamedLauncher-shots/hud-error-light.png. The error line uses the warning color (orange) with a triangle, not red, per DESIGN-SYSTEM.md's one warning color.

## M3 Timing and feedback

### S-016 Finish a known sequence with nothing on screen
As the user, I set `hudDelayMs` to 500 and fast sequences never show the HUD.
Depends: S-005
Acceptance:
- [unit] The HUD shows only after the delay passes with no key press. Every key, including Back, restarts the delay.
- [unit] Once shown, the HUD stays until the sequence ends.
Status: done

### S-017 Let an abandoned sequence time out
As the user, I set `timeoutMs` to 5000 and a forgotten HUD closes by itself.
Depends: S-016
Acceptance:
- [unit] The timeout runs only while the HUD is visible, and every key press restarts it.
- [unit] When `showHud` is false, the timeout never fires.
Status: done

### S-018 Get feedback for a key that isn't bound
As the user, a wrong key flashes the HUD and beeps, and the sequence stays where it was.
Screens: hud-error
Depends: S-005
Acceptance:
- [unit] An unbound key leaves the state unchanged and emits an error decision.
- [snap] With `errorFlash` true, the HUD shows a flash state.
- [unit] With `errorBell` true, an error decision plays the system alert sound, and with it false, no sound plays.
- [unit] If the HUD was still waiting for its delay, it appears at once.
Status: done
Verified: schedule rules (unit tests), flash on and off (self-test), /tmp/UnnamedLauncher-shots/hud-flash-light.png. The flash outlines the Guide in the accent.

### S-019 Choose where the HUD appears
As the user, I set `position` to center, top or bottom on the display of the app I'm using.
Screens: hud
Depends: S-005
Acceptance:
- [self] The HUD appears on the screen that holds the front app's key window, not the main screen.
- [snap] Center, top and bottom positions each have a snapshot.
Status: done
Verified: screen choice and positions (unit tests), the front app's screen and the top and bottom frames (self-test). Position snapshots were replaced by frame checks, because snapshots capture the panel alone, not the screen around it. Not yet tried by hand: a second display.

### S-020 Set the HUD theme
As the user, I set `theme` to system, light or dark.
Screens: hud
Depends: S-005
Acceptance:
- [snap] Light and dark snapshots both match the token colors, whatever the system appearance.
Status: done
Verified: appearance per theme (self-test); /tmp/UnnamedLauncher-shots/hud-theme-dark-on-light.png and hud-theme-light-on-dark.png, real captures with glass.

### S-021 Run sequences with no HUD at all
As the user, I set `showHud` to false and never see the panel.
Depends: S-016
Acceptance:
- [unit] With `showHud` false, sequences still resolve, errors still beep, and no panel is created.
Status: done
Verified: schedule rules (unit tests), no panel until first shown (self-test). Failures go to the log only when the Guide is off.

### S-022 Choose my own cancel and back keys
As the user, I set `cancelKey` to Q and `backKey` to an empty string to turn Back off.
Depends: S-007
Acceptance:
- [unit] The configured keys work, an empty `backKey` turns Back off, and binding a step to either key fails validation.
Status: done
Verified: custom cancel key and Back off (engine unit test), step keys that clash fail validation (unit tests), footer labels (self-test).

## M4 Bindings window and Settings

### S-023 See all bindings as a tree
As the user, I choose Edit Bindings… from the menu bar and see every leader, menu and binding in an outline.
Screens: bindings
Depends: S-001
Acceptance:
- [snap] A sidebar with Bindings, Actions and Contexts. Bindings shows an outline with key, title and action columns, in file order.
- [snap] An invalid config shows a banner above the outline listing the errors, and the outline shows the last valid config.
Status: done
Verified: /tmp/UnnamedLauncher-shots/bindings-light.png and bindings-error-dark.png (the banner over the last valid outline). Key, Title and Action columns; the action's type is in the Action cell's tooltip.

### S-024 Add a menu or binding
As the user, I select a menu and choose Add Binding or Add Menu (⌘N and ⇧⌘N).
Screens: bindings
Depends: S-023, S-033
Acceptance:
- [self] The new entry is added at the end of the selected menu, with its key recorder focused.
- [unit] Saving an entry with no key, or a key that's already taken in that menu, is blocked and the reason is shown inline.
Status: done
Verified: added at the end of the selected menu with the recorder on; not saved until it has an action, and says why (self-test).

### S-025 Record a key
As the user, I click a key field and press the chord or key I want.
Screens: bindings
Depends: S-024
Acceptance:
- [self] For a leader, the recorder captures a full chord. For a step, it captures one key with no modifiers.
- [unit] Recorded keys are stored in canonical form ("Hyper+Space", "A").
- [snap] A conflict with a sibling entry, or with the cancel or back key, is shown in red under the field.
Status: done
Verified: taken keys, modifiers inside a menu and the cancel key are refused with the reason; keys are stored in canonical form (self-test, unit tests). Not yet tried by hand: recording Hyper+Space as a leader.

### S-026 Edit a binding's title and action
As the user, I change a binding's title or pick a different action from a popup.
Screens: bindings
Depends: S-024, S-030
Acceptance:
- [self] Changing the title or action rewrites only that entry in the file.
- [unit] The action popup lists every defined action, plus "New Action…".
Status: done
Verified: the action popup's choices, and a title change rewrites one line (self-test).

### S-027 Delete an entry
As the user, I press Delete on a selected entry to remove it.
Screens: bindings
Depends: S-023, S-033
Acceptance:
- [self] Deleting a menu that has children asks first and names how many entries will go. ⌘Z restores them.
Status: done
Verified: counts entries under a menu, deletes them, ⌘Z restores (self-test). Not yet tried by hand: the confirmation dialog.

### S-028 Reorder a menu's items by dragging
As the user, I drag a binding up or down within its menu.
Screens: bindings
Depends: S-023, S-033
Acceptance:
- [self] The new order is written to the file, and the HUD then lists the items in that order.
- [self] An item can't be dropped into a different menu by dragging, because that would change its key path.
Status: done
Verified: the new order is saved and the Guide follows; no moving into another menu (self-test). Tried by hand on 2026-11-11: dragging in the outline.

### S-029 Sort a menu alphabetically
As the user, I choose Sort Alphabetically on a menu.
Screens: bindings
Depends: S-028
Acceptance:
- [unit] The children are sorted in three groups: named keys alphabetically with F-keys by number, then digits, then letters.
- [self] The command can be undone.
Status: done
Verified: sort order (unit tests), undo (self-test).

### S-030 Create and edit actions
As the user, I add an action, pick its type, and fill in a form for that type.
Screens: actions
Depends: S-023, S-033
Acceptance:
- [snap] A list of actions with their type and how many bindings use each, plus a form that changes with the type.
- [self] For `application`, the bundle id comes from an app picker (an Open panel limited to apps) or is typed in.
- [self] Renaming an action id updates every binding that uses it. Deleting an action that's in use is blocked and lists its users.
Status: done
Verified: /tmp/UnnamedLauncher-shots/actions-light.png; rename updates bindings, delete in use is blocked (self-test). Not yet tried by hand: the app picker.

### S-031 Define contexts
As the user, I create a "browser" context and add Chrome and Firefox to it.
Screens: contexts
Depends: S-030
Acceptance:
- [snap] A list of contexts in order, each showing its apps with their icons and names.
- [self] Contexts can be reordered by dragging, and the order is saved because it decides which variant wins.
Status: done
Verified: /tmp/UnnamedLauncher-shots/contexts-dark.png; reordering is saved (self-test). Tried by hand on 2026-11-11: dragging contexts.

### S-032 Change general settings
As the user, I open Settings… (⌘,) and set the Guide delay, timeout, position, theme, cancel and back keys, and feedback options.
Screens: settings
Depends: S-023, S-033
Acceptance:
- [snap] One grouped Form, 520 pt wide, with sections Guide, Keys, Feedback and Startup, and a short help line in each section footer.
- [unit] A negative delay can't be entered.
Status: done
Verified: /tmp/UnnamedLauncher-shots/settings-dark.png; negative delays become 0 (unit test); settings are written to the file (self-test).

### S-033 Save edits back to the config file
As the user, every change I make in the Bindings window or Settings is written to `config.json` right away.
Depends: S-001
Acceptance:
- [unit] A config loaded and saved with no edits keeps the same entry order, action order and contexts as the original.
- [unit] Output is pretty-printed with a stable key order, so edits make small diffs.
- [self] The write is atomic. A write that would produce an invalid config is refused, and the file isn't changed.
- [self] If the file changes on disk while the window is open, the window reloads it.
Status: done
Verified: round trip, layout, small diffs (unit tests); atomic save, refused invalid save, reload on disk change (self-test).

### S-034 Fix validation errors from the Bindings window
As the user, I click an error in the banner and the entry or action it names is selected.
Screens: bindings
Depends: S-023
Acceptance:
- [self] Clicking an error selects the right row and focuses the field with the problem.
Status: done
Verified: clicking an error selects its row and focuses the field (self-test).

## M5 System

### S-035 Reload automatically when the file changes
As the user, I save the config in my editor, or chezmoi rewrites it, and the new bindings work at once.
Depends: S-008
Acceptance:
- [self] A change to the file, including an atomic replace (write to a temp file, then rename), triggers a reload within 1 second.
Status: done
Done with S-033: the store watches the config's folder and reloads within about 150 ms of a change, including an atomic replace (self-test).

### S-036 Start at login
As the user, I turn on "Open at Login" in Settings.
Screens: settings
Depends: S-032
Acceptance:
- [self] The switch uses `SMAppService.mainApp` and reflects its current `status`. If you turn it off in System Settings, the switch shows off.
Status: done
Done with S-032: Open at Login in Settings › Startup uses SMAppService.mainApp and reads its status each time Settings opens. Not yet tried by hand.

### S-037 Recover when macOS turns off the event tap
As the user, I never lose my leader keys because macOS paused the tap.
Depends: S-003
Acceptance:
- [self] On `tapDisabledByTimeout` or `tapDisabledByUserInput`, the tap is turned back on and the event is logged.
Status: done
Verified: both disabled-tap events are handled by the tap and logged (self-test). Turning a real tap back on can't be forced in a test; the code calls CGEvent.tapEnable on the stored port.

### S-038 Know when a password field is blocking keys
As the user, the menu bar tells me when Secure Event Input is on, so I know why the leader doesn't work.
Screens: menubar-warning
Depends: S-002
Acceptance:
- [snap] While `IsSecureEventInputEnabled()` is true, the menu shows "Keyboard is secured by another app" with a short explanation.
Status: done
Verified: the menu section, warning icon and VoiceOver label (self-test, with Secure Input simulated). The state is read every two seconds with IsSecureEventInputEnabled(). Not yet tried by hand: a real password field.

### S-039 Get editor help from a JSON Schema
As the user, my editor validates and autocompletes `config.json`.
Depends: S-001
Acceptance:
- [unit] `config.schema.json` accepts the fixture config and rejects one sample of each type error.
- [self] The starter config includes a `$schema` reference, and loading ignores the `$schema` field.
Status: done
Verified: key paths the app accepts and rejects match the schema's pattern, action types match, delays have minimum 0 (unit tests); the schema is written next to the config (self-test). The tests check the schema's parts against the app rather than running a full JSON Schema validator, which would need a dependency.

## M6 Polish

### S-040 Welcome on first launch
As the user, on first launch I see what the app does, which permissions it needs, and where the config file is.
Screens: welcome
Depends: S-002, S-001
Acceptance:
- [snap] A small window with three steps: grant Accessibility, grant Input Monitoring, try Hyper+Space. Each step shows a check mark once done.
- [self] It shows only until both permissions are granted and you've run one sequence.
Status: done
Verified: /tmp/UnnamedLauncher-shots/welcome-light.png; the show-until-done rule (self-test). Steps get a check mark as each is done. "Later" closes it for now; it opens again at the next launch until setup is done. Not yet tried by hand: a real first launch.

### S-041 App icon and menu bar icon states
As the user, I can tell at a glance whether the launcher is ready, off, or needs attention.
Screens: menubar, menubar-warning, welcome
Acceptance:
- [snap] An app icon (Icon Composer, light, dark and tinted) and a template menu bar icon, the app icon's glyph, with normal, dimmed and warning states.
Status: done
Verified: design/icon-review.png (the app icon in Default, Dark, Tinted, Clear and at 32 and 16 pt) and design/menubar-icons.png (ready, off and warning on light and dark menu bars).

### S-042 Empty states in the Bindings window
As the user, an empty page tells me what to add and how.
Screens: bindings, actions, contexts
Depends: S-023
Acceptance:
- [snap] Each empty list shows one line of explanation and an Add button.
Status: done
Verified: /tmp/UnnamedLauncher-shots/empty-bindings-light.png, empty-actions-*.png and empty-contexts-*.png: one line of explanation and a New Menu, New Action or New Context button.

### S-043 Context menus in the outline
As the user, I right-click an entry to Add Binding Here, Duplicate, Sort Alphabetically or Delete.
Screens: bindings
Depends: S-024, S-027, S-029
Acceptance:
- [self] Every context menu item matches an item in the menu bar, with the same name and shortcut.
Status: done
Verified: every right-click item is in the menu bar, and Duplicate copies a subtree (self-test, unit test). The add item is called New Binding, as in the File menu, rather than Add Binding Here, so the two names match. Menus also offer New Menu and Record Key (⌘K). Not yet tried by hand: right-clicking.

### S-044 Use the Bindings window from the keyboard
As the user, I move through the outline with the arrow keys, press Return to edit a title, and press Space to record a key.
Screens: bindings
Depends: S-025
Acceptance:
- [manual] Every action in the Bindings window and Settings can be done without a mouse.
- [self] VoiceOver reads each row as "key, title, action".
Status: done
Verified: VoiceOver row labels and Return to edit the title (self-test). Arrows move through the outline, Space and ⌘K record a key, ⌫ deletes, and every command is in the menu bar. Not yet tried by hand: the whole window and Settings with the keyboard only, and with VoiceOver on.

## M7 Refinements

### S-045 Actions listed alphabetically
As the user, I find an action by name, because every list of actions is in alphabetical order.
Screens: actions, bindings
Depends: S-026, S-030
Acceptance:
- [unit] Action ids sort without regard to case, and numbers sort by value ("open-2" before "open-10").
- [self] The Actions page and the action popup in the Bindings editor list actions in that order, wherever each action is in the file.
- [unit] The file keeps the order of its `actions` object; only the lists are sorted.
Status: done
Verified: sort order and file order (unit tests), the popup's choices and a new action sorting first (self-test), the Actions page in light and dark (snapshots). Not yet tried by hand: the action popup in the Bindings editor.

## M8 Guide Icons

### S-054 See app icons in the Guide
As the user, I see each app's icon next to its Use Application binding in the Guide, so I can find the app I want before I read its title.
Screens: hud, hud-home
Depends: S-005, S-046, S-050
Acceptance:
- [unit] A row whose action is Use Application carries its bundle ID; rows with other actions, menus, and Context Aware rows carry none.
- [self] A row for an installed app gets that app's icon, looked up once per bundle ID and cached for the rest of the run.
- [self] A row for an app that isn't installed gets no icon and still shows its title, with no error.
- [self] When any row in a Guide column has an icon, every row in that column keeps the same icon space, so titles line up; a column with no app rows has none.
- [self] Opening the Guide never waits on an icon lookup: icons come from the cache, filled when the config loads.
- [snap] The Guide and Home show 24 pt icons between the keycap and the title, in light and dark, with the grid checks passing.
- [manual] VoiceOver reads a row the same as before: the icon is decorative.
UX:
- Surface: the Guide (S-005) and Home (S-050). The Help page (S-052) is out of scope.
- States: icon; no icon (not installed, or not Use Application); a dimmed row dims its icon too.
- Words: none new.
- Access: icons are hidden from VoiceOver.
Status: done
Verified: bundle IDs on rows and the set of apps (unit tests, AppIconTests); the cache, a missing app, the icon column and no lookups when the Guide shows (self-test); hud and hud-home in light and dark (snapshots), grid checks. Not yet tried by hand: VoiceOver on a row with an icon.

### S-055 See file, folder and URL icons in the Guide
As the user, I see the Finder icon of the file or folder an Open binding opens, and for a URL the icon of the app that opens it, so the rows I open things from are as easy to spot as my apps.
Screens: hud
Depends: S-054
Acceptance:
- [unit] An Open row carries its target: a path with a leading ~ expanded, or a URL; menus and other actions carry none.
- [self] A file or folder that exists gets its Finder icon; one that doesn't gets no icon and no error.
- [self] A URL gets the icon of the app that opens it, such as the default browser for https.
- [self] Icons are looked up when the config loads, never when the Guide shows, as for apps (S-054).
- [snap] An Open row shows its icon in the same 24 pt space as an app's.
UX:
- Surface: the Guide and Home.
- States: icon; no icon (missing file, no app for the URL).
- Words: none new.
Status: done
Verified: icon sources for apps, files, folders and URLs (unit tests, IconTests); a folder, a missing file, a URL, the fixture's Open row, no lookups when the Guide shows (self-test); hud in light and dark (snapshots), grid checks.

### S-056 Choose an icon for any entry
As the user, I give a menu or a binding an icon of my own, an SF Symbol or a file's icon, so rows the launcher can't guess an icon for are easy to spot too.
Screens: hud, bindings
Depends: S-054, S-055
Acceptance:
- [unit] An entry's optional `icon` is an SF Symbol name, or a path starting with / or ~ for that file's Finder icon; it is written back unchanged, and left out when empty.
- [unit] The schema lists `icon` as an optional string on entries.
- [self] An entry's own icon wins over its action's icon.
- [self] An SF Symbol name macOS doesn't have shows no icon in the Guide, and the Bindings editor says "No SF Symbol named “X”."
- [self] Setting and clearing the icon in the Bindings editor writes the file, and Undo restores it.
- [snap] Symbols are drawn in secondary color, centered in the 24 pt icon space; the editor shows an Icon field with a preview and a menu of common symbols.
UX:
- Surface: the entry form on the Bindings page, under Title.
- Words: "Icon", hint "An SF Symbol name, such as terminal, or the path of a file whose icon to use."
- Access: icons stay hidden from VoiceOver in the Guide; the editor's preview is labeled with the symbol name.
Status: done
Verified: reading, writing, empty icons, symbols and paths, the entry's icon winning, the schema (unit tests); setting, clearing and undoing in the editor, the unknown-symbol message, no icon for an unknown symbol (self-test); hud and bindings-icon in light and dark (snapshots), grid checks. Not yet tried by hand: VoiceOver on the Icon field's preview.

## M9 Unnamed Manager

The launcher becomes Unnamed Manager: new name, new bundle id, new config folder, and the shared spec's rule ids. Nothing else changes, so you can use it for a day exactly as you used the launcher.

### S-057 Run as Unnamed Manager
As the user, I install Unnamed Manager and see its name everywhere the launcher's was: the menu bar menu, the Bindings window, Settings, Help, the Welcome window and the log.
Screens: welcome, help, settings, menubar
Acceptance:
- [unit] The Swift targets are `UnnamedManager` and `UnnamedManagerKit`; the bundle id is `net.unnamed.manager`; `build.sh` installs `UnnamedManager.app`.
- [unit] The config file is `~/.config/unnamed-manager/config.json` (`APP_STORE` still overrides it), and the schema is written next to it.
- [self] Every window title, menu item and log line says "Unnamed Manager"; no "Unnamed Launcher" is left in the app's own text, except in S-058.
- [self] The event tap thread is named `net.unnamed.manager.event-tap`.
- [snap] Welcome, Help and Settings show the new name in light and dark.
- [manual] macOS asks for Accessibility and Input Monitoring again, because the bundle id is new, and the Welcome window walks through both.
- [manual] The Homebrew cask is `unnamed-manager`, and the release workflow updates it.
Status: done
Verified: targets, bundle id, config path and no old name in the sources (unit tests, AppNameTests, ConfigLocationTests); 122 self-test checks; welcome, help and settings in light and dark (snapshots), grid checks. The signing certificate keeps its name, "Unnamed Launcher Code Signing", so the release secrets still work. The v0.1.0 release installs with `brew install --cask unnamed-manager` (2026-11-11): version 0.1.0, quarantine cleared, the app runs and keeps the permissions granted to a local build. Not yet tried by hand: granting the permissions on a Mac that never had the app.

### S-058 Bring over my launcher config
As the user, I start Unnamed Manager for the first time and copy my Unnamed Launcher config with one click, so my leaders and bindings carry over, and the app tells me if Unnamed Launcher is still running and capturing the same keys.
Screens: welcome-import, welcome-copied (the menu bar menu isn't captured)
Depends: S-057
Acceptance:
- [self] With no config and `~/.config/unnamed-launcher/config.json` present, Welcome offers to copy it (Copy Config); it copies the file, never moves or changes the original, and loads the copy.
- [self] With no launcher config, Welcome writes the starter config as before.
- [self] An existing Unnamed Manager config is never overwritten.
- [self] While `net.unnamed.launcher` is running, the menu bar menu and Welcome say "Unnamed Launcher Is Running" with a Quit Unnamed Launcher button, and the menu bar icon shows its warning badge.
- [snap] Welcome with the copy offer, in light and dark.
UX:
- Flow: first launch → the app writes the starter config as before → Welcome shows "Copy Your Unnamed Launcher Config" with Copy Config → the copy replaces the starter and loads → the row shows a check mark and "Copied from ~/.config/unnamed-launcher/config.json". Way back: the launcher's file is never touched; Open Config File shows what was copied.
- Surface: an inline row in the Welcome window, above the three steps (one value on a screen already open). The running warning is a section of the menu bar menu, like Needs Permission, and the same line in Welcome.
- States: offer (no Unnamed Manager config before this launch, the starter is unchanged, a launcher config exists); copied; not offered (no launcher config, or the config isn't the untouched starter); copy failed, inline: "Unable to copy the config: <reason>"; launcher running.
- Words: row title "Copy Your Unnamed Launcher Config", detail "Your leaders, bindings, actions and contexts, in place of the starter config.", button "Copy Config"; after: "Copied from ~/.config/unnamed-launcher/config.json". Menu section "Unnamed Launcher Is Running", line "It may take the same keys. Quit it to use Unnamed Manager alone.", button "Quit Unnamed Launcher".
- Access: Copy Config is a normal button in the tab order; the row reads as one element with its state ("Copied" once done).
Status: done
Verified: the offer rules, copying, the old file untouched, no offer with no old config, an existing or edited config never overwritten, the warning badge (13 self-test checks); welcome-import and welcome-copied in light and dark (snapshots), grid checks; AppNameTests keeps the old name in LauncherMigration.swift only. Not yet tried by hand: a real first launch with ~/.config/unnamed-launcher/config.json present, and Quit Unnamed Launcher from the menu.

### S-059 Name the rule behind every config error
As the maintainer, I see which rule from the shared spec each config error and warning comes from, so the Mac and Windows apps can be checked against the same fixtures.
Screens: none (no UI)
Depends: S-057
Acceptance:
- [unit] Every `ConfigIssue` carries a rule id from `spec/CONFIG-SPEC.md`, Validation, decoding errors included (`invalid-json`, `unknown-field`, `missing-field`, `wrong-type`, `unknown-action-type`, `bad-app-mode`).
- [unit] `SpecFixtureTests` checks each fixture's rule as well as its subject.
- [unit] Messages are unchanged; the rule id never shows in the UI.
Status: done
Verified: every issue about the file's contents carries a `ConfigRule`; SpecFixtureTests checks the rule and subject of all 45 fixtures and that the app's rules are exactly the ids in the spec's Validation tables (unit tests, checked by breaking one rule on purpose). Messages are unchanged (existing tests pass). Issues outside the file's contents (a file that can't be read or saved, a draft binding with no action) have no rule.

## M10 Action registry

Each action family becomes a module, so window actions, and later volume or display resolution, are added without touching the engine, the Guide or the Bindings window. No behavior changes. Run `improve-architecture` for this milestone, one step per commit.

### S-060 Add an action family as one module
As the maintainer, I add a new kind of action by writing one module and registering it, and the config reader, the validator, the schema, the Guide, the Actions page and the runner all pick it up.
Screens: actions, hud
Depends: S-059
Acceptance:
- [unit] A family declares its `type` values, decodes and checks its own fields (unknown fields and missing fields reported with the spec's rule ids), writes itself back in a stable key order, adds its part of the JSON Schema, and gives its UI name, default SF Symbol and action plan.
- [unit] Six of the seven existing types are families; Context Aware stays in the shell, since it combines other actions. Every existing test passes unchanged, and the generated schema is byte-for-byte the same.
- [unit] A family registered only in the tests loads from JSON, appears in the schema and the Type picker's list, and runs through `RecordingPerformer`, with no change to shared files.
- [self] The self-test's action plans are unchanged.
- [snap] The Actions page and the Guide look the same as before, in light and dark.
Status: done
Verified: the schema, the starter and every valid spec fixture written back are byte-for-byte the golden files from before the change (`ActionGoldenTests`); 155 unit tests, including `ActionRegistryTests` and a Beep family added only in the tests (`TestFamilyTests`); 141 self-test checks, including a Chime family in its own file that loads, shows in the Type picker, records its step and runs it; actions, actions-app, actions-help, hud and bindings in light and dark (snapshots), grid checks.

## M11 Window actions

Manage the window in front from the keyboard. The spec repo settles the fields first (S-061), then each action is built on the registry. After this milestone you can drop any other window tool for one-shot commands.

The fields, ranges and geometry are in `spec/CONFIG-SPEC.md`, Window actions (spec v2). Each story takes its fixtures off `SpecFixtureTests.pending`, and S-069 the last one, `valid/window-actions.json`.

Every window action works on the **focused window of the app in front**, the same app the Guide leaves in front. A failure (no window, a window that can't move) ends the sequence and shows as for any failed action: in the Guide, or with the error sound for a direct binding.

Window gotchas to respect throughout:
- Accessibility positions use a top-left origin on the primary display; `NSScreen` uses bottom-left. Convert in one place in the Kit, and test it with displays above, below and left of the primary one.
- Set size, then position, then size again: a window near a screen edge can't grow until it has moved.
- Browsers and Electron apps animate frame changes while `AXEnhancedUserInterface` is on. Turn it off for the move and put it back after.
- Some windows have a minimum or fixed size. Place them as close as they allow, anchored to the edge they belong to, and don't call it a failure.
- Full-screen windows are left alone, with a failure that says so.

### S-061 Settle the window action fields in the shared spec
As the maintainer, I decide each window action's fields in the spec repo, with fixtures, and tag `spec-v2`, so the Mac and Windows apps build the same format.
Screens: none (no UI)
Depends: S-059
Acceptance:
- [unit] `spec/CONFIG-SPEC.md` defines `window.focus`, `window.place`, `window.move`, `window.resize`, `window.maximize` and `window.minimize`: every field, its range, its default, and its validation rule ids.
- [unit] The open questions on `version` and on what an unsupported type does are answered in the spec.
- [unit] `fixtures/manifest.json` has a valid fixture with every window action and every field, and one invalid fixture per new rule.
- [unit] The spec repo is tagged `spec-v2`, and the `spec/` submodule is moved to it. `SpecFixtureTests` fails on the new fixtures until S-062 to S-069 are done; mark them pending until then.
Status: done
Verified: `spec-v1` tagged at the v1 commit and `spec-v2` at the window actions; the spec defines the six window types, their fields, ranges and defaults, the shared geometry, four new rule ids (`conflicting-fields`, `bad-fraction`, `bad-window-value`, `unsupported-action`), and answers the `version` and unsupported-type questions. 19 new fixtures; `SpecFixtureTests.pending` lists each with the story that builds it, and a pending fixture that starts passing fails the test (checked by adding a passing one). 156 unit tests pass with 19 known issues. `unsupported-action` has no fixture until a type exists on one platform only.

### S-062 Maximize the window in front, and restore it
As the user, I press a key and the window fills the usable area of its screen; I press it again and it goes back to where it was.
Screens: none (no UI)
Depends: S-060, S-061
Acceptance:
- [unit] The target frame is the `visibleFrame` of the screen that holds most of the window.
- [unit] A window already filling that frame (within 2 pt) goes back to the frame it had before Maximize; with no remembered frame, nothing changes.
- [unit] The remembered frame is per window and kept in memory only; a window that moved since Maximize forgets it.
- [self] Against a fake window: Maximize, then Maximize again, restores the first frame exactly.
- [self] No focused window fails with "<App> has no window to maximize."
- [manual] In Zed and in Safari, Maximize and restore in one step each, with no animation in Safari.
Status: done
Verified: screen choice, the coordinate flip, fill, restore, per-window memory, a moved window forgetting, an app that snaps its size, and reading, writing and planning `window.maximize` (unit tests, `WindowGeometryTests`, `MaximizeTests`); its schema is the spec's (`SpecSchemaTests`), and `window-toggle-type.json` is off the pending list. Against `FakeWindowSystem`: fill, restore exactly, a window with a maximum size, no focused window, no Accessibility (self-test, 146 checks). Not yet tried by hand: the manual line.

### S-063 Minimize the window in front
As the user, I press a key and the window goes to the Dock.
Screens: none (no UI)
Depends: S-060, S-061
Acceptance:
- [self] Against a fake window, Minimize sets it minimized.
- [self] No focused window fails with "<App> has no window to minimize."
- [manual] The app in front stays the same app; focus moves to its next window, as when you press ⌘M.
Status: done
Verified: reading, writing, planning and rejecting a field on `window.minimize` (unit tests); its schema is the spec's, and `window-unknown-field.json` is off the pending list. Against `FakeWindowSystem`: minimized, and no focused window (self-test, 148 checks). Not yet tried by hand: the manual line.

### S-064 Place the window on a half, third, quarter or corner
As the user, I press a key and the window moves and resizes to a part of the screen, such as the left half or the top right quarter.
Screens: none (no UI)
Depends: S-060, S-061
Acceptance:
- [unit] A placement is a frame in fractions of the usable area; presets cover halves, thirds, two thirds, quarters and center, and each one maps to the expected frame on screens of several sizes.
- [unit] Fractions turn into whole points, and two neighbouring placements (left half, right half) share an edge with no gap or overlap.
- [unit] The coordinate conversion is right with a second display above, below, left and right of the primary one.
- [self] A fake window with a minimum size larger than the placement ends as close as it allows, anchored to the placement's edge.
- [manual] Left half then right half in Zed, Safari and Ghostty, on the built-in display and an external one.
Status: done
Verified: presets on four screen sizes, shared edges and whole points, the coordinate flip for displays on every side, anchoring, reading, writing and planning `window.place`, an unknown field inside `frame` (unit tests, `PlaceTests`); its schema is the spec's, and five fixtures are off the pending list. Against `FakeWindowSystem`: a window with a minimum width keeps the right edge on the right half and the left edge on the left half (self-test, 150 checks). Not yet tried by hand: the manual line. The form comes with S-070.

### S-065 Grow or shrink the window through preset widths
As the user, I press one key to make the window wider and another to make it narrower, stepping through widths I chose, such as 25 %, 33 %, 50 %, 66 % and 75 % of the screen.
Screens: none (no UI)
Depends: S-064
Acceptance:
- [unit] The next width is the smallest preset wider than the window now (or the largest narrower one, for shrink); at the end of the list it stays put rather than wrapping.
- [unit] The window keeps its left edge, unless that would push it off screen, when it keeps its right edge.
- [unit] With no `widths` in the action, the default list is 1/4, 1/3, 1/2, 2/3 and 3/4.
- [manual] Grow from a narrow Zed window to 75 % and back down, one key per step.
Status: done
Verified: the next width, the 2-point tolerance, stopping at the ends, keeping the left or right edge, unordered widths, the default list, and reading, writing and planning `step` and `widths` (unit tests, `ResizeStepTests`). The whole `window.resize` format came with this story, so its schema is the spec's and seven resize fixtures are off the pending list. Grow twice against `FakeWindowSystem` (self-test). Not yet tried by hand: the manual line.

### S-066 Move the window by a step or to a position
As the user, I nudge the window by a set number of points, or send it to an exact spot, such as centered or the top left corner.
Screens: none (no UI)
Depends: S-064
Acceptance:
- [unit] `by` moves by points; `to` places the window at fractions of the free space (the usable area less the window's size), so `{ 0, 0 }` is the top left corner, `{ 0.5, 0.5 }` centered and `{ 1, 1 }` the bottom right.
- [unit] A move never leaves the window entirely off screen: at least 40 pt of its title bar stays on its screen.
- [self] Against a fake window, its size is unchanged after a move.
Status: done
Verified: `to` at fractions of the free space, a window wider than the area, `by` in points, the title bar kept on every side, and reading, writing and planning `window.move` (unit tests, `MoveTests`); its schema is the spec's, and two fixtures are off the pending list. Three moves against `FakeWindowSystem` keep the size and end with 40 points on screen (self-test, 152 checks).

### S-067 Resize the window by a step or to an exact size
As the user, I make the window bigger or smaller by a set amount, or set it to an exact fraction of the screen, keeping one corner or the center in place.
Screens: none (no UI)
Depends: S-064
Acceptance:
- [unit] `by` changes width and height by points; `to` sets them as fractions of the usable area.
- [unit] The anchor (a corner, an edge or the center) stays where it was; the default anchor is the top-left corner.
- [unit] The result is clamped to the usable area.
- [self] A fake window with a fixed size reports no failure and stays as it was.
Status: done
Verified: `by` and `to` sizes, all nine anchors, clamping, and reading, writing and planning `to` and `by` (unit tests, `ResizeTests`); the format and its fixtures came with S-065. Against `FakeWindowSystem`: a fixed-size window stays as it was with no failure, and Resize to half keeps the bottom right corner (self-test, 154 checks).

### S-068 Focus the nearest window left, right, up or down
As the user, I press a direction key and the window next to the one I'm in comes to the front with focus, even if it's on another display.
Screens: none (no UI)
Depends: S-060, S-061
Acceptance:
- [unit] Candidates are the standard, visible, not minimized windows on the current Spaces of every display; panels, the Guide and the app's own windows are skipped.
- [unit] The nearest window is the one whose center is closest in that direction, within a 45° cone of it; ties go to the one with more overlap on the other axis.
- [unit] With no window that way, it fails with "No window to the left." (right, above, below).
- [self] With fake windows in a 2×2 grid across two displays, each direction picks the expected window.
- [manual] Focus moves between Zed and Ghostty side by side, and across to the external display, and the focused window gets the keys.
Status: done
Verified: the nearest center, the 45° cone, the overlap tie-break, each direction, the failure for each, and reading, writing and planning `window.focus` (unit tests, `FocusDirectionTests`); its schema is the spec's, and with it every spec v2 fixture passes: the pending list is empty and `valid/window-actions.json` has its own writer golden file (194 unit tests). Against `FakeWindowSystem`, a 2×2 grid across two displays gives the expected window in all eight moves, and no window to the left leaves focus where it was (self-test, 156 checks). Candidates on a real Mac (on-screen windows matched to Accessibility windows by owner and frame, this app's skipped) are checked only by hand: the manual line.

### S-069 Focus the next or previous window
As the user, I press a key to go to the next window, and another to go back, in a fixed order I can predict.
Screens: none (no UI)
Depends: S-068
Acceptance:
- [unit] The order is by display, left to right, then by window center, top to bottom and left to right; it wraps at the ends.
- [unit] The same set of windows always gives the same order, whatever was focused last.
- [self] With fake windows, next from the last window goes to the first.
Status: done
Verified: the order across a display on each side, the same order for the same windows in any input order (owners and sizes break ties), wrapping both ways, starting from a window not in the list, and no other window (unit tests, `FocusCycleTests`, 199 in all). Against `FakeWindowSystem`, Next from the last window goes to the first and Previous comes back (self-test, 157 checks).

### S-070 Set up window actions on the Actions page and see them in the Guide
As the user, I choose a window action from the Type picker, set its options with pickers instead of typing JSON, and see an icon for it in the Guide.
Screens: actions-window, hud-window
Depends: S-062, S-063, S-064, S-065, S-066, S-067, S-068, S-069
Acceptance:
- [self] The Type picker lists Focus Window, Maximize, Minimize, Move Window, Place Window and Resize Window with the existing types, alphabetically.
- [self] Each type's form has the right controls: a Direction picker for Focus Window; a preset menu plus four fraction fields for Place Window; presets or step fields for Move and Resize; a list of widths for grow and shrink.
- [self] Saving each form writes the fields the spec defines, and Undo restores the file.
- [self] The snapshot fixture config has a Windows menu with one binding of each window action.
- [snap] The Actions page with each window form, and the Guide on the Windows menu with each action's SF Symbol, in light and dark, with the grid checks passing.
UX:
- Flow: Actions page → Add Action (+) or pick an action → Type: Place Window (or any window type) → the form's first picker already has a good default (Left Half, Center, Grow Through Widths, Right) → change a picker or a number → it saves as you go → ⌘Z undoes each change. Way back: ⌘Z, or pick another type.
- Surface: inline, in the action's form on the Actions page (changes values on something already on screen), like every other type. No sheets or popovers.
- States: a preset or spot picked → its numbers show below it; change a number → the picker says Custom. Numbers are clamped as you type (a frame never runs past the screen, widths stay 1 to 100 %), so the form never makes an invalid file. Widths left empty → the field's prompt shows the default list. A failure when the action runs shows in the Guide as for any action ("No window to the left.").
- Words: types Focus Window, Maximize, Minimize, Move Window, Place Window, Resize Window. Pickers: "Direction" (Left, Right, Up, Down, Next Window, Previous Window); "Preset" (Left Half … Bottom Right Quarter, Center, Custom); "Move" (To a Spot, By Points) with "Spot" (Center, Top Left … Bottom Right, Custom); "Resize" (Grow Through Widths, Shrink Through Widths, To a Size, By Points); "Keep in Place" (Top Left Corner, Top Edge, … Center). Fields "X", "Y", "Width", "Height" in % of the screen; "Right", "Down", "Wider", "Taller" in points; "Widths" as a list of percentages. Toggle "Press Again to Restore". Footers say what the screen means here: "without the menu bar and Dock".
- Guide: each type has an SF Symbol, and Place Window and Focus Window show the preset or direction (rectangle.lefthalf.filled, arrow.left.square, …). An entry's own `icon` still wins.
- Access: every picker and field has a label VoiceOver reads ("Width, percent of the screen"); percent and point units are in the label, not only in a suffix; the whole form works with Tab and the arrow keys.
Status: done
Verified: the Type picker lists the six window types with the others, alphabetically; each form's value is saved as the spec writes it, and Undo puts the file back exactly (self-test, 160 checks). The forms' controls are checked on their snapshots, not by the self-test: actions-window-left-half, -move-center, -wider, -half-size, -focus-right and -maximize, plus hud-window, in light and dark; grid checks pass (the lint now skips the window geometry, whose numbers aren't layout). The seed config has a Windows menu under Commands with one binding of each window action. Not yet tried by hand: VoiceOver on the number fields, and typing widths.

### S-071 Leave a gap around placed windows
As the user, I place windows on halves and thirds and they stand a little apart from each other and from the screen's edges, by a gap I can change in Settings.
Screens: settings
Depends: S-064
Acceptance:
- [unit] `windows.gap` (spec v3) defaults to 8, is written only when changed, and a negative gap is `negative-gap`; the spec-v3 fixtures pass and the schema's `windows` object is the spec's.
- [unit] Edges on the screen's edge move in by the whole gap and edges inside it by half, so neighbouring presets end exactly one gap apart, for even and odd gaps; a centered placement moves in by half on every side; a window keeps at least 1 point.
- [self] Against `FakeWindowSystem` with a gap of 8, the left and right halves stand 8 points from the edges and from each other, and a window wider than its half keeps its right edge one gap in.
- [snap] Settings has a Windows section with Gap Between Windows, in light and dark, and every section fits.
UX:
- Flow: Settings… (⌘,) → Windows → Gap Between Windows → type a number or use the stepper (0 to 64, steps of 2) → saved at once → ⌘Z undoes.
- Surface: inline, a row in Settings (changes one value on screen).
- Words: section "Windows", row "Gap Between Windows", unit "pt", footer "Place Window leaves this space between a window and the screen's edges, and between windows side by side. 0 puts them edge to edge."
- Access: VoiceOver reads "Gap between windows, points".
Status: done
Verified: 204 unit tests (`WindowGapTests`, `SpecSchemaTests`, the spec-v3 fixtures); the two gap checks against `FakeWindowSystem` (self-test, 162 checks); settings in light and dark, grid checks. Settings now grows to 960 points, or 80 points short of a shorter screen. Move, Resize and Maximize don't use the gap.

### S-072 Focus the window in front when no window has focus
As the user, I press a Focus Window key while no window has focus, such as with the desktop in front or after closing an app's last window, and the window in front of the others takes focus.
Screens: none (no UI)
Depends: S-068, S-069
Acceptance:
- [self] With fake windows and none focused, every direction, Next and Previous go to the window in front of the others, also when no app is in front.
- [self] With no window at all, it fails with "No window to focus."
- [manual] With Finder's desktop in front and no Finder window, a Focus Window key focuses the window on top.
Status: done
Verified: both checks against `FakeWindowSystem` (self-test). The real front-to-back order (the window server's) is checked only by hand: the manual line. The rule is in `spec/CONFIG-SPEC.md`, `window.focus` (spec v5).

### S-073 Focus the first or last window
As the user, I press a key and the leftmost window takes focus, and another for the rightmost, and Next and Previous walk the windows between them from left to right.
Screens: actions-window
Depends: S-069, S-072
Acceptance:
- [unit] `window.focus` reads and writes `first` and `last` (spec v6); the schema lists them and `valid/window-focus-ends.json` passes.
- [unit] The order is by display, left to right, then by window center, left to right and then top to bottom.
- [self] With fake windows, First and Last go to the two ends of the order, also with no focused window, and stay put on a window that's already there.
- [self] With no window at all, First fails with "No window to focus."
- [snap] Focus Window's Direction picker has First Window and Last Window, and the footer says what they do.
UX:
- Words: "First Window", "Last Window"; footer "Next Window and Previous Window go through windows from left to right, display by display. First Window and Last Window go to the leftmost and the rightmost."
Status: done
Verified: the new order, the two values and their golden file (unit tests, `FocusCycleTests`, `ActionGoldenTests`, the spec-v6 fixtures); both checks against `FakeWindowSystem` (self-test); actions-window in light and dark, grid checks. This changes S-069's order: stacked windows used to come top to bottom before left to right.

### S-074 Fill the screen, with the gap
As the user, I press a key and the window fills its screen, the same gap from the edges as my placed windows; I press it again and it goes back to where it was.
Screens: actions-window, settings
Depends: S-062, S-071
Acceptance:
- [unit] `window.fill` reads, writes and plans as Maximize did (spec v7); the schema lists it and `valid/window-fill.json` passes.
- [unit] `window.maximize` still loads, runs as Fill, and is written back as `window.maximize`.
- [unit] The frame to fill is the usable area, one gap in from every edge; a window within 2 pt of it goes back.
- [self] With a gap of 8, Fill stands 8 points from every edge, and pressed again restores the first frame exactly, also under the old name.
- [self] The Type picker offers Fill once, and not under its old name.
- [snap] The Fill form and the Gap footer in Settings both say Fill leaves the gap.
UX:
- Words: type "Fill"; footer "Fills the screen without the menu bar and Dock, less the gap from Settings. Not full screen."; Settings footer "Place Window and Fill leave this space…".
- Place Window stays plain: it puts the window where it says, and pressing it again does nothing.
Status: done
Verified: reading, writing, planning, the old name and the gapped area (unit tests, `FillTests`, `ActionGoldenTests`, the spec-v7 fixtures); the gap, the restore and the picker against `FakeWindowSystem` (self-test, 169 checks); actions-window-fill and settings in light and dark, grid checks. This renames S-062's Maximize. Not yet tried by hand on real windows.

### S-075 Arrange the windows used last in a grid
As the user, I press a key and the window I'm using and the one I used before it stand side by side in halves, or more of them in columns or rows, with the gap.
Screens: actions-window
Depends: S-064, S-068, S-071
Acceptance:
- [unit] `window.arrange` reads, writes and plans `count` (2 to 8), `groups` and `layout` (spec v8); the schema lists it and the spec-v8 fixtures pass.
- [unit] The grid: equal groups of equal cells, edges shared between neighbours on any width; any count in any number of groups fills the usable area.
- [unit] Windows keep their order from left to right, then top to bottom; windows in the same spot go by use, the more recent one further right or up.
- [unit] When the grid has more cells than windows, the focused window stays in the group its center is in and takes the spare cells there (five windows in three columns: it fills its column); the others keep their order in the other cells. With more spare cells than its group has, other groups with one window are on the right or at the top. Run again, from any window, nothing else moves.
- [unit] With fewer windows than cells, the cells on the left and at the bottom stay empty.
- [self] Two fake windows end in halves, 8 points apart; a third window, a window on another display and the focus stay as they were; run again, nothing moves.
- [self] With no focused window, the one in front counts as focused; with no window, it fails with "No window to arrange."
- [snap] The Arrange Windows form has Windows, Groups and Layout, and a footer that says where windows go.
UX:
- Words: type "Arrange Windows"; pickers "Windows" (Last 2 to Last 8, All on the Display), "Groups" (Automatic, 1 to 8), "Layout" (Automatic, Columns, Rows). The glossary's words: cell, group.
- No toggle and no memory, as with Place Window.
Status: done
Verified: the grid, the order, ties, the focused window taking the spare cells where it is, empty cells, and reading, writing and planning (unit tests, `ArrangeTests`, `ActionGoldenTests`, the spec-v9 fixtures); halves, the other display, running it again, rows, no focused window and no window against `FakeWindowSystem` (self-test); actions-window-arrange in light and dark, grid checks. Not yet tried by hand on real windows.

### S-076 Arrange every window on the display, within limits from Settings
As the user, I press a key and every window on the display I'm on gets a cell, and Settings says how many columns and rows that may take.
Screens: actions-window, settings
Depends: S-075
Acceptance:
- [unit] `"count": "all"` arranges the windows on the display, at most Maximum Columns times Maximum Rows, and never more than 8; older windows stay as they are.
- [unit] Without `groups`, the grid has as many groups as cells, up to the maximum for its layout; an automatic layout is rows on a tall display.
- [unit] `windows.maxColumns` and `windows.maxRows` are read, written only when they aren't 2, and rejected outside 1 to 8 (`bad-window-limit`).
- [self] With three fake windows, All gives the focused one the whole column it's in and stacks the others in the other; run from a window on the left, that one fills the left column; with Maximum Columns at 3 they're three columns.
- [self] Changing Maximum Columns in the editor saves it in the file.
- [snap] Settings has Maximum Columns and Maximum Rows under Gap Between Windows.
UX:
- Words: "Maximum Columns", "Maximum Rows"; footer "The maximums limit the grid Arrange Windows picks when its action leaves Groups on Automatic."
Status: done
Verified: the limit, the automatic groups and layout, and the two settings (unit tests, `ArrangeTests`, `invalid/window-limit.json`); both arrangements and the saved setting (self-test, 178 checks); settings in light and dark, grid checks. Not yet tried by hand on real windows.
### S-077 Swap the window in front with another
As the user, I press a key and the window I'm in trades places with the one to its left, or the next one, the first one, or window number 2, and I stay in it, so pressing again keeps moving it the same way.
Screens: actions-window, hud-window, settings
Depends: S-068, S-069, S-073
Acceptance:
- [unit] `window.swap` reads, writes and plans `target` (a direction, `next`, `previous`, `first`, `last`, or an integer from 1) and `scope` (spec v10); the schema lists it and the spec-v10 fixtures pass.
- [unit] A direction picks the window Focus Window would focus; Next and Previous wrap; First, Last and numbers count in Focus Window's order from 1, so 1 is First.
- [unit] A target that is the focused window does nothing and isn't a failure; past the last window it says "No window 4. There are 3."
- [self] Swap left trades frames with the window on the left and focus stays; Swap right puts them back; a number swaps across displays.
- [self] With no window there, nothing moves, it says so, and it plays the alert sound; with no focused window it says so without the sound.
- [self] A window with a minimum size keeps the edge on the screen's edge.
- [self] The alert sound plays only for no window there, and not with Play Alert Sound off.
- [snap] The Swap Window form has Swap With, Number for Window Number, and Windows; the Guide shows its symbols; the Feedback footer in Settings mentions the sound.
- [manual] Two real windows side by side swap and swap back, and a missing window beeps (and flashes the screen with that turned on in Accessibility settings).
UX:
- Words: type "Swap Window"; pickers "Swap With" (Left … Last Window, Window Number), "Number" (a stepper, 1 to 99), "Windows" (On Every Display, On the Same Display). Footer says the window keeps focus and you hear the alert sound with no window there.
- The sound is `NSSound.beep()`: the user's alert sound, which macOS also turns into a screen flash when that's on in Accessibility.
Status: done
Verified: picking the window for every kind of target, staying put, the failures, reading, writing, planning and the icons (unit tests, `SwapTests`, `ActionGoldenTests`, the spec-v10 fixtures, 233 in all); the swaps, focus, the failures and their sound, a window with a minimum size, and saving the form against `FakeWindowSystem` (self-test, 190 checks); actions-window-swap-left, -swap-2, hud-window and settings in light and dark, grid checks. Not yet tried by hand on real windows.

### S-078 Keep Focus Window and Swap Window to one display
As the user, I choose On the Same Display for a Focus Window or Swap Window key, and it never jumps to my other display: Next wraps on the display I'm on, and Left stops at its edge with the alert sound.
Screens: actions-window
Depends: S-068, S-077
Acceptance:
- [unit] `window.focus` reads and writes `scope` (spec v10), written only when it isn't `all`; a bad scope is `bad-window-value`.
- [self] Focus right on the same display fails with "No window to the right." and the alert sound; on every display it crosses over.
- [self] Last on the same display is the rightmost window there; Next swaps within the display.
- [self] Focus Window finding no window plays the alert sound (spec v10).
- [snap] The Focus Window form has a Windows picker, and its footer says what On the Same Display does.
Status: done
Verified: reading and writing (unit tests, `FocusScopeTests`, `invalid/window-focus-scope.json`); both displays against `FakeWindowSystem` (self-test); actions-window-focus-next in light and dark, grid checks. The default stays every display, as before.

### S-079 Bind built-in actions without defining them, and override them
As the user, I write `"action": "window-place-left-half"` or `"window-focus-left"` in a binding and it works with nothing in `actions`; when I use another window manager, I define an action called `window-focus-left` that runs its command, and every binding with that name runs mine instead.
Screens: actions-window
Depends: S-077, S-078
Acceptance:
- [unit] Built-in names follow spec v11's rule: the type with hyphens for its dots, then a value of its main field in lowercase words joined by hyphens, every other field at its default. Fill, Minimize, Place Window, Resize Window's grow and shrink, Arrange Windows, Focus Window, Swap Window, Show Help and Do Nothing have them; names are case-sensitive, numbers have no leading zero, and Arrange Windows stops at 8.
- [unit] An action in `actions` with a built-in name overrides it, with no warning; any other name a binding uses that's neither is `undefined-action`.
- [unit] Focus Window reads `target`, which also takes a number from 1; `direction`, its old name, still loads and is written back as the file had it; both is `conflicting-fields`. The spec-v11 fixtures pass.
- [self] Focus Window 3 goes to the third window from the left, with no focused window too; 4 of 3 fails with "No window 4. There are 3." and the alert sound.
- [self] A built-in name runs its action as a binding does, and an action with that name runs instead.
- [snap] Focus Window's form has Focus On, with Window Number and a Number stepper as Swap Window has.
UX:
- Words: "built-in action", "override" (glossary). The Action picker's Built In section and the Actions page's override label come with S-080.
Status: done
Verified: the names, every rejected spelling, the listed names, overrides, the old field name, conflicts and numbers (unit tests, `BuiltInActionTests`, `FocusTargetTests`, the spec-v11 fixtures, 241 in all); numbers, the alert sound, a built-in name and an override against `FakeWindowSystem` (self-test, 193 checks); actions-window-focus-right and -focus-next in light and dark, grid checks. Not yet tried by hand.

### S-080 Choose built-in actions in the Bindings window, and see overrides
As the user, I pick Place Window › Left Half from a binding's Built In menu and the binding works with nothing to set up; on the Actions page I can tell which of my actions override a built-in one, and deleting an override gives me the built-in one back. A new config starts with a Windows menu of built-in actions.
Screens: bindings-builtin, actions-window, hud-window
Depends: S-079
Acceptance:
- [self] Choosing a built-in action saves its name in the binding and nothing in `actions`.
- [self] An action with a built-in name runs instead of it, and deleting it while bindings use it is allowed and gives them the built-in action back.
- [unit] The listed built-in actions each stand for their own action, none twice (`window-arrange-2` loads but isn't listed, being `window-arrange`).
- [unit] The starter config has a Windows menu of built-in actions and Help as the built-in `help`, and loads with no warnings.
- [snap] A binding with a built-in action shows "Swap Window: Left" in its Action picker, under Built In, with a Built In menu below it; an override's ID footer says it overrides the built-in action and how to get it back.
UX:
- Flow: Bindings window → select a binding → Built In → Choose → a family (Place Window, Focus Window, Swap Window, Arrange Windows, Resize Window) → a value, or Fill, Minimize, Show Help or Do Nothing directly → saved, ⌘Z undoes.
- Words: "Built In", "Your Actions" (picker sections); "Place Window: Left Half"; "override" in the Actions list; footer "This one overrides the built-in action of the same name; delete it to use the built-in one again."
- Numbers (Window 1, Window 2…) aren't in the menu, since they have no end; a binding gets one by name in the file, or with a Focus Window or Swap Window action.
Status: done
Verified: saving a built-in name and deleting an override in use (self-test, 195 checks); the listed names and the starter (unit tests, 241); bindings-builtin, actions-window-window-fill and hud-window in light and dark, grid checks. The open Built In menu isn't in a snapshot (menus can't be captured); not yet tried by hand.

### S-081 See every built-in action on the Help page
As the user, I open Help and find the built-in actions, kind by kind, with the name to write in my config next to what each one does, and I can tell which ones my own actions override.
Screens: help, help-builtin
Depends: S-079, S-080
Acceptance:
- [self] Help lists every built-in action, in the same kinds and order as the Built In menu, with a row for Focus Window's and Swap Window's numbered windows.
- [self] A built-in action the config overrides says "Overridden by your action".
- [snap] Built-In Actions sits after In a Sequence: a row for Fill, Minimize, Show Help and Do Nothing, and a list to open for each other kind, with its count; names are monospaced and can be selected and copied.
UX:
- Words: section "Built-In Actions"; rows "Left Half … window-place-left-half"; "14 actions"; "Window 1, 2, 3…"; footer "A binding can use these with nothing to set up: choose one from its Built In menu, or write its name as the binding's action in the config file. An action of your own with the same name overrides it."
- Which kinds are open is kept while the app runs (`AppModel.openBuiltIns`); `showBuiltIns(_:)` opens one and scrolls to it, waiting `Motion.layoutSettle`, with no animation.
Status: done
Verified: the list and the override mark (self-test, 197 checks); help and help-builtin in light and dark, grid checks. Not yet tried by hand: copying a name.

### S-082 Focus and swap only the windows I can see, in reading order
As the user, I press Focus Right or Swap Down and get the window I see there, even when it's bigger or smaller than mine or partly behind it, and never one hidden behind other windows; Window 2 in a 3×2 grid is the top middle one.
Screens: actions-window
Depends: S-068, S-069, S-073, S-077, S-079
Acceptance:
- [unit] A window counts only when its visible part (its frame minus the windows in front of it) holds a 20 by 20 point square; the focused window always counts (spec v12).
- [unit] A direction picks among visible parts past the focused window's center: windows in line first, then the smallest gap, the most shared span, the nearest center across, the one in front; with none in line, the 45° rule on the centers of those parts.
- [unit] From the top half, Down finds a quarter-width window below; from a small window inside a large one, every direction finds the large one; with two windows stacked on the left, Right from the front one goes right and the hidden one is skipped by every target.
- [unit] The order is row-major: by display, then rows of tops within 20 points, top to bottom, then left to right; a 3×2 grid is 1 to 3 across the top; a full-height left window and two stacked on the right read left, right top, right bottom.
- [self] Focus Window and Swap Window skip a window hidden behind another, by direction, Next and number.
- [unit] `windows.minVisible`, `rowTolerance` and `tieTolerance` default to 20, 20 and 2, are written only when changed, and a negative one is `negative-window-distance`; the spec-v12 fixtures pass.
UX:
- No new fields in the forms. The Focus Window and Swap Window footers say "the windows you can see", "in rows, as you read", and that hidden windows are skipped. Settings has a Focus and Swap section with "Smallest Visible Part", "Same Row Within" and "Equally Near Within", in points, with a footer that says what each does.
Status: done
Verified: visible parts, the square across parts, every direction case, the order, the settings and the rule (unit tests, `SeenWindowTests`, the spec-v12 fixtures, 254 in all); stacked windows by direction, Next, number and swap, and a window inside a larger one against `FakeWindowSystem`, which now raises a focused window (self-test, 201 checks, with Smallest Visible Part saved and undone); actions-window-focus-right, -swap-2, settings and settings-bottom in light and dark, grid checks. Not yet tried by hand on real windows.

### S-083 Focus or swap with the window I used before
As the user, I press one key to go back to the window I used before, and again to come back, even when it's on my other display, on another Space, or behind the window I'm in; with another key, my window and that one trade places and I stay in mine. If I closed that window, I get the one I used before it. Apps I list never get picked by any Focus Window or Swap Window key.
Screens: actions-window, settings
Depends: S-077, S-079, S-082
Acceptance:
- [unit] `window.focus` and `window.swap` read and write `"target": "recent"` (and `direction` too); `window-focus-recent` and `window-swap-recent` are built-in actions; the spec-v13 fixtures pass.
- [unit] The focus history puts a window first each time it gets focus, holds each window once, and keeps at most 10.
- [unit] `recent` picks the first window in the history that's a candidate (not minimized, not an excluded app, on the scope's displays) and isn't the focused one; whether you can see it doesn't matter. With nothing in the history yet, it's the front-most other candidate. With none, "No window used before."
- [unit] `windows.exclude` is a list of app ids, empty by default and written only when it isn't; a window of an excluded app is never picked by any target, and isn't in the order.
- [self] Focus Recent twice goes back and forth between two windows, across displays and when one is fully covered; after the previous window closes, it goes to the one before it; with no other window, nothing moves and the alert sound plays.
- [self] Swap Recent trades frames with the window used before, focus stays, and pressing again swaps them back; a window on another Space is skipped.
- [manual] Focus Recent from a window on one Space goes back to a window on another, also when both are the same app's.
- [self] Settings saves an app Left Out of Focus and Swap in `windows.exclude`, and undo works.
- [manual] Two real windows on two displays, and two stacked windows: Focus Recent goes back and forth; Cmd+Tab and clicks count as focus changes.
UX:
- Words: target "Window Used Before" in Focus On and Swap With; the footer says Previous goes by order and Window Used Before by when you used it. Settings gets a "Left Out of Focus and Swap" section after Focus and Swap: each app with its icon, name and bundle id and a Remove button, then "Add App…" (an open panel in /Applications), as on the Contexts page. Glossary: "window used before".
- The history is kept by the app while it runs, not in the config: app switches (NSWorkspace) and each app's focused-window changes (an AX observer per app), plus what the app's own actions focus. It keeps each window's AX element: a window on another Space isn't in its app's AX window list, but its saved element still answers, and AXRaise then activate moves to its Space (tried by hand with two Safari windows, 2026-11-17).
Status: done
Verified: the history, the pick, the target, built-in names, the old field name and the setting (unit tests, `FocusHistoryTests`, the spec-v13 fixtures, 258 in all); back and forth across displays, a covered window, another Space, a closed window, no window, swap and swap back, swap skipping another Space, an excluded app, and saving the setting against `FakeWindowSystem`, which now has Spaces and clicks (self-test, 209 checks); actions-window-focus-recent, hud-window and settings-bottom in light and dark, grid checks. Not yet tried by hand: Accessibility's focus reports, and another Space with two different apps.
Later: `windows.exclude` and its Settings section gave way to `windows.apps` and the Apps table (S-084, spec v15).

### S-084 Choose for each app which window actions take part
As the user, I keep Calculator out of Arrange Windows, so it floats where I put it, while Focus Window and Swap Window still go to it; or the other way round, for an app I never want to focus by key but do want arranged. One table shows each app's choices.
Screens: settings
Depends: S-075, S-083
Acceptance:
- [unit] `windows.apps` maps app ids to `focus`, `swap` and `arrange`, each true when missing; every listed app is written with all three; a rule that isn't one is `unknown-field`, one that isn't a boolean `wrong-type`; `windows.exclude` (spec v13 and v14, never released) is `unknown-field`; the spec-v15 fixtures pass.
- [self] Focus Window never picks an app with `focus` false; Arrange Windows never counts or moves one with `arrange` false and still arranges one with only `focus` and `swap` false; with the focused window left out, its display is arranged and the window in front there takes the focused one's cell.
- [self] Swap Window never moves an app with `swap` false, as the one swapped with or the focused one ("Calculator is left out of Swap Window."), and still swaps with one with only `focus` false.
- [self] Settings saves an app's three rules, and undo works.
UX:
- Settings: an "Apps" section, a table with App, Focus, Swap and Arrange columns, a checkbox for each, checked when that action takes part, and a Remove button; then "Add App…". A new app starts with every box unchecked, since you add an app to leave it out of something. Glossary: "Apps (Settings)".
Status: done
Verified: the rules, defaults, writing all three, `unknown-field`, `wrong-type` and the dropped `exclude` (unit tests, `FocusHistoryTests`, the spec-v15 fixtures, 260 in all); Focus, Swap and Arrange Windows with each rule, and saving the rules (self-test); settings-bottom in light and dark, grid checks. Not yet tried by hand on real windows.
Later: the Apps table moved to Settings' Windows tab (S-085).

### S-085 Edit my bindings in Settings, with the rest of my settings
As the user, I find my bindings where I find every other setting: one Settings window, as in Xcode's Key Bindings and Mail's Rules, so there's one window for setup and it comes up in front of the app I'm in.
Screens: general, bindings, actions, contexts, windows, help
Depends: S-023, S-032, S-052
Acceptance:
- [self] Settings has the tabs General, Bindings, Actions, Contexts and Windows, opens on Bindings, and switches tabs; there's no Bindings window.
- [self] Settings… brings the app and the Settings window in front of another app, from the menu bar with no window open.
- [self] Help opens a window of its own; a key on it brings Settings back on the Bindings tab.
- [self] The window can be resized, opens with a 980 × 640 page, and switching tabs never resizes it, before or after you resize it.
- [snap] Every tab and Help in light and dark; a list's add and remove buttons in a bar under it.
- [manual] From the menu bar while another app is in front, Settings… and Help open in front, with no other copy of the app running.
UX:
- The menu bar menu has Settings… (⌘,) in place of Edit Bindings… (⌘B). The View menu switches tabs with ⌘1 to ⌘5. The title names the tab. Glossary: "Settings", "Help window"; "Bindings window" and "Help page" are retired.
- ⌘Q still quits: it's the app menu's Quit Unnamed Manager, as in every Mac app. ⌘W closes the window.
Status: done
Verified: tabs, no Bindings window, one size on every tab, resizing and keeping the size, Help as its own window, and Settings… and Help in front of another app with no window open (self-test, 222 checks); every tab, empty tabs and Help in light and dark, grid checks. The front checks are skipped while another copy of the app runs, since NSWorkspace brings the copy with the same bundle id forward.

### S-086 Quit an app when I close its last window
As the user, I close an app's last window and the app quits, as on Windows, so apps I'm done with don't pile up in the Dock. Finder and the apps I choose stay open.
Screens: windows
Depends: S-084
Acceptance:
- [unit] `windows.quitOnClose` is false by default and `quit` in `windows.apps` true; the Mac app writes `quit` with the other three rules; one that isn't a boolean is `wrong-type`; `windows.quitOnCloseDelayMs` is 500 by default and negative is `negative-delay`; the spec-v16 fixtures pass.
- [unit] With it on, an app whose last window closed quits. Finder and this app never quit, nor does an app with `quit` false or an app inside one, an app that never showed a window, a hidden app, a menu bar app, or an app with a window left (minimized or on another Space).
- [unit] An app kept open (Finder, or Quit unchecked) that closed its last window and is still in front hands focus to the window used before, as an app that quits does; not one you've left, nor one that quits.
- [self] Settings saves Quit on Close, Wait After Closing and an app's Quit rule, and undo works.
- [manual] With it on, closing TextEdit's last window quits TextEdit; closing Finder's doesn't, and the window you used before gets focus; minimizing TextEdit's last window doesn't; with Quit unchecked for TextEdit, it stays open.
UX:
- Settings' Windows tab: a "Quit on Close" section before Apps with "Quit Apps When Their Last Window Closes", and a fourth column, Quit, in the Apps table. Finder's Quit box is unchecked and can't change. Glossary: "Quit on Close".
- An app is counted Wait After Closing (500 ms, under the switch, greyed out while it's off) after a window closes, so one that opens a new window in its place stays. Floating panels, such as an inspector, don't keep an app open; dialogs do.
- Focus moves through Focus Window's Window Used Before (S-083), in the launcher's window actions, which keep the history. Nothing sounds when there's no window to go to.
- Off in snapshots and the self-test, so a test config never quits your apps.
Status: done
Verified: the setting, the rule, `wrong-type`, every keep and quit case and helper apps (unit tests, `QuitOnCloseTests`, the spec-v16 fixtures); saving and undo (self-test); windows and windows-bottom in light and dark, grid checks. Tried by hand (2026-11-18): TextEdit quits when its last window closes, and Finder hands focus to the window used before.

### S-087 Get reminded of the Spaces settings window actions suit
As the user, I see on Settings' Windows tab, and in the menu bar menu, when "Automatically rearrange Spaces based on most recent use" is on or "Displays have separate Spaces" is off, and I change them there without looking for them in System Settings.
Screens: windows-bottom
Depends: S-085
Acceptance:
- [unit] Both are on when their key isn't set; `mru-spaces` in com.apple.dock is Rearrange, and `spans-displays` in com.apple.spaces is the opposite of Separate Spaces; a test domain prefix reads and writes its own domain.
- [self] Turning Rearrange off writes `mru-spaces` false and restarts the Dock once; turning Separate Spaces off writes `spans-displays` true, restarts nothing, and says it waits for log out; both in test domains.
- [snap] A Spaces section ends the Windows tab with both switches, a suggestion under each one that isn't as suggested, and Open Desktop & Dock Settings….
- [self] Reduce Motion (Accessibility › Motion) shows as On or Off with a note, as an optional tip: never in the menu bar's Suggested, and the app only reads it, since it changes animations across the Mac. Off, the note says Spaces would fade instead of sliding; on, that they do. Open Accessibility Settings… opens the Accessibility pane (no anchor for Motion was found).
- [manual] Turning Rearrange off asks before restarting the Dock, then System Settings shows it off. With either one not as suggested, the menu bar menu has Suggested › Review Spaces Settings…, which opens the Windows tab.
UX:
- Suggestions, not requirements: the menu bar icon gets no badge, and nothing else changes when they're left as they are.
- Words: System Settings' own names in title case. "Suggested off, so each Space keeps its place…", "Suggested on, so each display has its own Spaces…". Separate Spaces changes when you log out, and the section says so until then.
- These are macOS settings, not the config file, so there's no undo and nothing in `spec/`.
- Snapshots and the self-test use test domains (`net.unnamed.manager.test.`) and never restart the Dock.
Status: done
Verified: the keys and their meaning (unit tests, `SpacesSettingsTests`); writing, the Dock restart and the log-out note, Reduce Motion's note off and on and that it's never a suggestion (self-test, 290 checks); windows-bottom in light and dark, grid checks. Not yet tried by hand: the manual line, and the Reduce Motion row following a change in System Settings while the tab is open.

### S-088 Switch Space with a key, with no slide
As the user, I press a key to go to the Space to the left or right on the display I'm working in, the focused window's, and I'm there at once, without the sliding animation macOS plays for Control-Left and Control-Right.
Screens: actions-window, hud-window, help-builtin
Depends: S-079, S-087
Acceptance:
- [unit] `space.switch` reads and writes `"target": "left"` and `"right"`; no target is `missing-field`, any other value `bad-window-value`; `space-switch-left` and `space-switch-right` are built-in actions; the spec-v17 fixtures pass, and its schema's `space.switch` matches the app's.
- [unit] The quick switch builds a Began, Changed and Ended dock swipe, each paired with a gesture event; on macOS 27 and later each carries the raw input payload, and Ended has the high velocity for its direction.
- [self] Switch Space is in the Actions page's Type picker, alphabetically, with a Direction picker (Left, Right); it saves `target` and undoes.
- [self] Running it switches through the window system seam (`WindowSystem.switchSpace`), so the self-test's `FakeWindowSystem` takes it and nothing reaches the real Dock.
- [self] It switches the focused window's display, the one with the largest part of it, wherever the pointer is; with no focused window nothing is posted; neither that nor the last Space is a failure or plays a sound.
- [snap] The Switch Space form, the Guide row on the sample Windows menu, and the Help window's Built-In Actions list.
- [manual] With five Spaces, Switch Space Right then Left moves one Space each way with no slide, in under 100 ms (the 2026-11-18 test took about 40 ms on macOS 27.2.1); held down, it moves one Space per press; with Displays Have Separate Spaces on and the pointer on the other display, the focused window's display switches and the pointer ends where it was.
- [manual] At the last Space, nothing moves, or macOS bounces.
UX:
- Glossary: "Switch Space" (spec v17). Form: "Direction" with Left and Right; text "Goes to the Space to the left or right, without the slide. Full-screen apps count as Spaces."
- Built-in names keep the spec rule: `space-switch-left`, `space-switch-right`. The starter config doesn't bind them.
- Which display: a swipe switches the display macOS picks, likely the one with the pointer (to check first). If so, the app moves the pointer to the focused window's display for the swipe and puts it back after (CGWarpMouseCursorPosition), and when the pointer is already there it doesn't move it.
- How: the same events a fast three- or four-finger swipe sends, posted with CGEventPost at the session tap, as in joshuarli/iss (ISC). It needs only Accessibility, which the app has. On macOS 27, events without the raw input payload (field 4205) are ignored.
- Risk: the event fields and the payload are undocumented, so a macOS update can bring back the slide or stop the switch. The app can't tell when the Dock ignores the events (macOS 27 reports the active Space late), so there's no failure to show. A [manual] check on each new macOS release, and Control-Left and Control-Right as the fallback, written in the form's help.
Status: done
Verified: reading, writing, the rules, built-in names, the swipe's events and payload bytes (unit tests, `SpaceSwitchTests`, the spec-v17 fixtures, 281 in all); left and right on the focused window's display, the last Space, no focused window, no Accessibility, the Type picker and saving (self-test, 231 checks); actions-window-space-right, hud-window and help-builtin in light and dark, grid checks. The swipe itself was tried by hand on 2026-11-18 with a test tool, before the app had it: about 40 ms per switch on macOS 27.2.1. Not yet tried by hand in the app: the manual lines, including whether the leader's held modifiers or the event location change anything.

### S-096 Send a window to another Space
As the user, I press a key such as `CAG+Quote 2` to put the focused window on Space 2 of its display and keep working where I am; with Go With the Window on, I go there with it. When I change tasks, I send a window or two to the Space for the new one.
Screens: actions-window, help-builtin
Depends: S-088
Acceptance:
- [unit] `space.send` reads and writes `target` (`left`, `right`, or a number from 1) and `follow` (false is left out); no target is `missing-field`, `0`, `"up"` and `"2"` are `bad-window-value`, a `follow` that isn't a boolean is `wrong-type`; `space-send-left`, `space-send-right` and `space-send-N` are built-in actions with `follow` off; the spec-v20 fixtures pass.
- [unit] Where it goes: left and right stop at the ends with no failure, the window's own Space does nothing, a number past the last desktop fails ("No Space 5. There are 4."), and a full-screen window or one on every Space can't be sent.
- [self] Through the window system seam (`WindowSystem.desktop`, `.send`), so `FakeWindowSystem` takes it and no real window moves: you stay and the window used before on this Space takes focus; with follow you go there and the window keeps focus; failures play the sound; no Accessibility says so.
- [self] With follow, after the quiet move you go there by Switch Space's swipe, one per Space on the window's display (Space 2 to 4 is two swipes right), so there's no slide and no Switch to Desktop shortcut is needed.
- [self] Send to Space is in the Type picker with Send To (Space to the Left, Space to the Right, Space Number), a Number stepper and Go With the Window; Help lists its built-in actions with a row for Space 1, 2, 3….
- [snap] The Send to Space form and the Help window's Built-In Actions list.
- [manual] `CAG+Quote 2` on a window on Space 1 puts it on Space 2 with no slide, and focus goes to the window used before on Space 1; with follow, you're on Space 2 with the window in front, with no slide, also when the Dock's “switch to a Space with open windows” is off and when the target is two or more Spaces away.
- [manual] When macOS refuses the quiet move, the title bar is held and the Switch to Desktop shortcut pressed: the window arrives, and without follow you're back on your Space.
UX:
- Glossary: "Send to Space" (spec v20). Form: "Send To" with "Space to the Left", "Space to the Right" and "Space Number"; "Number" (1 to 16, the Mac's Switch to Desktop shortcuts); "Go With the Window". Footer says how numbers count, what follow does, and that the fallback needs the shortcut on.
- Errors, with the sound: "No window to send.", "No Space 5. There are 4.", "Safari's window is full screen, so it can't go to another Space.", "Safari's window is on every Space.", "Turn on “Switch to Desktop 3” in System Settings › Keyboard › Keyboard Shortcuts › Mission Control, so windows can go to Space 3.", "macOS didn't move the window. Hold its title bar and press the shortcut for Space 3."
- How (research/send-to-space.md): SkyLight's `SLSBridgedMoveWindowsToManagedSpaceOperation`, submitted with the non-exported function found in SkyLight's symbol table, works with SIP on in macOS 26 and 27.2. It returns before the move and says nothing when refused, so the app reads the window's Space back for half a second. Nothing that needs SIP off.
- Fallback: hold the title bar (the middle of the top edge, 6 pt down), press the Switch to Desktop N shortcut read from `com.apple.symbolichotkeys` (118 and up), let go after 700 ms, put the pointer back, and without follow press the shortcut for the Space you came from. It waits up to a second for the leader's modifiers to be let go, since Control with a click is a right click.
- Risk: macOS 27.3 beta 2 refuses the bridged move from apps other than the Dock (yabai #2853). Then the fallback is the only route, and it slides.
Status: done
Verified: reading, writing, the rules, built-in names and where a window goes (unit tests, `SpaceSendTests`, the spec-v20 fixtures, 330 in all); stay and follow, the focus after, the ends, the window's own Space, past the last, full screen, every Space, a refused move, no window, no Accessibility, the Type picker and saving, Help's rows (self-test, 281 checks); actions-window-send-3 and help-builtin in light and dark, grid checks. The app's SkyLight code, run alone on 2026-11-18 on macOS 27.2.1 with SIP on, found desktop 1 of 5, moved a test window to Space 2 and back, and saw a window on every Space. Tried by hand on 2026-11-18 by the user: `space-send-N` works. On 2026-11-19 the user found follow could leave them behind and patched it to press Switch to Desktop N, which slides; on 2026-11-21 follow swipes instead, as Switch Space does (self-test, 288 checks). Not yet tried by hand: follow by swipes, more than one swipe in a row (60 ms apart), the title bar fallback in the app, and a second display.
### S-097 Switch to a Space by number
As the user, I press a key such as `CAG+Space 2` to go straight to Space 2 of the display I'm working in, without the slide, even from an empty desktop, instead of pressing Space Right twice.
Screens: actions-window, help-builtin
Depends: S-088, S-096
Acceptance:
- [unit] `space.switch` also reads and writes a number from 1 (spec v22); `0`, `"2"` and `1.5` are `bad-window-value`; `space-switch-1` and the other numbers are built-in actions, `space-switch-0` isn't; the spec-v22 fixtures pass, and the schema matches the spec's.
- [unit] Where it goes (`SpaceSwitch.pick`): numbers count desktops only; the swipes pass full-screen Spaces too (desktop 1 to desktop 2 past a full-screen app is two swipes right); the Space you're on does nothing; a number past the last desktop fails ("No Space 4. There are 3.").
- [self] Through the window system seam (`WindowSystem.spaces(on:)`, `.switchSpace`), so `FakeWindowSystem` takes it: one swipe per Space on the focused window's display, 60 ms apart; with no focused window, on the display with the pointer; past the last desktop the sound plays and nothing moves.
- [self] The Switch Space form has Go To (Space to the Left, Space to the Right, Space Number) and a Number stepper, as Send to Space's; Help lists a "Space 1, 2, 3…" row under Switch Space.
- [snap] actions-window-space-1 and actions-window-space-right.
- [manual] From Space 1 of 4, `space-switch-3` reaches Space 3 with no slide; with a full-screen app between, it still lands on desktop 3; from an empty desktop, it switches the display with the pointer; `space-switch-9` plays the sound.
UX:
- Glossary: "Switch Space" (spec v22 adds numbers). Form: "Go To" with "Space to the Left", "Space to the Right" and "Space Number"; "Number" (1 to 16). Footer says how left and right and numbers count, and where a number works with no window in front.
- How: SkyLight's `SLSCopyManagedDisplaySpaces` gives the display's Spaces and the current one, found by the display's UUID (one list when Displays have separate Spaces is off); then Switch Space's swipe, once per Space between. No Switch to Desktop shortcut, so nothing slides.
- Error, with the sound: "No Space 4. There are 3.", and "Unable to find the Spaces of this display." when SkyLight doesn't say.
Status: done
Verified: reading, writing, the rules, built-in names and the pick (unit tests, `SpaceSwitchTests`, the spec-v22 fixtures, 332 in all); swipes by number, the Space you're on, past the last, full-screen Spaces, no focused window, Help's row (self-test, 297 checks); actions-window-space-1 and actions-window-space-right in light and dark, grid checks. Not yet tried by hand: the manual line, including the SkyLight lookup of the current Space and a second display.

## M12 Held menus

Hold a leader's modifiers to work its menu, as ⌘Tab does, and let go to choose. Then a menu the app fills itself, Recent Windows, gives a ⌘Tab for windows with number keys. The rules are in `spec/CONFIG-SPEC.md`, Held menus and Lists (spec v18), and `SPEC.md`, Held menus and Lists. The research and every decision behind them: `research/held-menus.md`.

Gotchas to respect throughout, from other switchers' worst bugs:
- One key press moves the highlight once. Key repeats never move it (AltTab #3117).
- Letting go is read from the set of modifiers held, never from counting events, so kanata's burst and a hand's slow release choose the same item.
- A missed key-up never leaves a held menu open: check `flagsState` while one is open.
- A chosen window goes first in the focus history at once (AltTab #5575).
- Nothing in the tap's callback waits on Accessibility or the window list.

### S-089 Settle held menus and lists in the shared spec
As the maintainer, I decide held menus and lists in the spec repo, with fixtures, and tag `spec-v18`, so the Mac and Windows apps build the same thing.
Screens: none (no UI)
Depends: S-083
Acceptance:
- [unit] `spec/CONFIG-SPEC.md` defines `hold` and `list`, the held menu rules, Recent Windows' fields and defaults, and the rule ids `step-is-repeat-key`, `hold-not-leader`, `hold-no-modifiers`, `list-has-children`, `unknown-list-type` and `bad-list-value`.
- [unit] `fixtures/manifest.json` has `valid/held-menus.json` and one invalid fixture per new rule, 148 in all.
- [unit] The spec repo is tagged `spec-v18`, and the `spec/` submodule moves to it with the first story that reads it, S-090. `SpecFixtureTests` marks the new fixtures pending until S-090, S-092 and S-093 take them off.
Status: done
Verified: spec v18 committed and tagged on 2026-11-18 (`9803aa9`); every fixture parses, and the manifest's paths are real. Pushed to the spec repo's main branch.

### S-090 Hold a leader and let go to choose
As the user, I give a leader Hold, and then I hold its modifiers, press its key again to move along, and let go to run what's highlighted: CAG+A, let go, runs the first item, and CAG+A A A, let go, the third.
Screens: none (S-091 shows it)
Depends: S-089
Acceptance:
- [unit] `hold` reads and writes on leaders; `hold-not-leader`, `hold-no-modifiers` and `step-is-repeat-key` (with the digit rule for a held list) are reported with their subjects; the spec-v18 fixtures for them pass, and the schema's `hold` matches the app's.
- [unit] The engine: opening a held menu highlights its first item after Cancel; the repeat key moves on and wraps through Cancel; Shift with it moves back, but not with a Shift leader such as Hyper; Down and Up move unless an item has that key; a binding's key moves the highlight there; a menu's key opens that menu held; key repeats do nothing.
- [unit] Letting go: the first leader modifier up chooses, for all six orders in which ⌃, ⌥ and ⌘ can come up; a binding runs; a menu goes on as an ordinary menu with no modifiers held; Cancel ends with nothing run and no failure; an unavailable Context Aware binding stays in its menu, now ordinary.
- [unit] No timeout while held, and `timeoutMs` once a chosen menu goes on. Back from a held leader's menu opens Home, and Home isn't held. A leader without Hold works exactly as before, including `CAG+D`, let go, `S`.
- [self] A missed key-up: with the tap turned off during a hold, the menu chooses within 200 ms of the modifiers being up (`flagsState` through a seam the self-test fakes).
- [manual] With kanata's Caps as CAG and a held CAG+A: tap and let go runs the first item; holding and pressing A twice runs the third; holding A down moves once; Escape cancels. Put off on 2026-11-21: Recent Windows on Alt+Tab, with a number key for each window (S-092 to S-095), covers it well enough for now. The refactor it would prompt, window commands as values the Kit decides (M11 and M12 architecture reviews), is put off with it.
UX:
- Glossary (spec v18): "Held menu", "Highlight", "Repeat key", "Cancel". The log says "Chose Browser" when letting go runs it.
- Nothing shows on screen until S-091's Guide; this story is the engine and the tap.
Status: done
Verified: hold, its three rules, the engine's highlight, repeat key, Shift, Down and Up, key repeats, choosing for all six release orders, Cancel, Back and Home, an unavailable binding, the timeout and the Guide's delay (unit tests, `HeldMenuTests`, the spec-v18 fixtures for hold, 305 in all, with the nine list fixtures pending for S-092); the schema's `hold` matches the spec's (`SpecSchemaTests`), and the golden schema was recorded again for it; a missed key-up chooses within 200 ms and is logged, and a disabled tap hands the engine the modifiers held and never a key (self-test, 235 checks). Not yet tried by hand: the manual line.

### S-091 See the highlight in the Guide
As the user, when I pause in a held menu, the Guide shows Cancel at the top and which item letting go will choose, and if I know where I'm going and let go first, nothing appears at all.
Screens: hud-held
Depends: S-090
Acceptance:
- [snap] `hud-held`: a held menu with Cancel first (no keycap), the highlight on an item in the accent, and the other rows as in any menu, in light and dark.
- [self] The highlight row follows the repeat key, Shift, Down and Up; Back moves the highlight to the menu you came from; a menu chosen by letting go shows as an ordinary menu, with no Cancel and no highlight.
- [self] Letting go before `hudDelayMs` chooses with the Guide never shown; each key press restarts the delay, as in any sequence.
- [manual] The highlight never lags a key press, and a fast tap and release shows no flash.
UX:
- Flow: hold the leader → (after `hudDelayMs`) the Guide with the first item highlighted → the repeat key, Shift, Down, Up or an item's key move it → let go chooses; Escape cancels, Back goes up.
- Surface: the Guide itself, the HUD the sequence already uses (changes one value on screen: which row is highlighted).
- The highlight: the whole row, keycap to `›`, filled with `Palette.accent` in `Radius.row`, like a selected menu item. Title, note and `›` in `Palette.onAccent`; the keycap keeps its own fill. The Guide's second use of the accent (DESIGN-SYSTEM.md). It's a shape, not only a color, so it reads with Differentiate Without Color and Increase Contrast.
- Cancel: the first row, an `xmark` symbol in the keycap's column in `.secondary` and the title "Cancel" in `.secondary`; highlighted, it takes the accent like any row.
- States: one item (Cancel and the item); only Cancel (highlighted); an unavailable item highlighted keeps its "not available in Notes" note, in `onAccent`.
- Words: footer "Let go to choose" first, then esc Cancel and delete Back. Glossary: Held menu, Highlight, Repeat key, Cancel.
- Motion: none. The highlight moves in the same frame as the key, with no animation, so Reduce Motion needs nothing.
- VoiceOver: opening a held menu says "Apps, Terminal, 1 of 4"; each move says only the item, "Browser, 2 of 4".
Status: done
Verified: Cancel first with no key, the announcements, the highlight following the repeat key, Shift and Up, Back highlighting the menu you came from, a chosen menu shown as ordinary, and letting go before the delay with the Guide never shown (self-test, 243 checks); hud-held in light and dark, every other page unchanged, grid checks. The highlight spans the Guide in one column, since the footer can make the Guide wider than the column. Not yet tried by hand: the manual line, and VoiceOver.

### S-092 Go back to any recent window with Recent Windows
As the user, I hold CAG and press H to see my recent windows, most recent first, then press H again or a number and let go to go to that window, even when it's minimized, hidden, or on another Space; a quick CAG+H goes back to the window I used before, as before, and right back again.
Screens: hud-recent
Depends: S-091
Acceptance:
- [unit] `list` with `"type": "windows.recent"` and `count`, `minimized`, `hidden`, `spaces` and `scope` reads and writes, with defaults left out on save; `list-has-children`, `unknown-list-type`, `bad-list-value`, `conflicting-fields` (both `action` and `list`) and `missing-field` (no `type`) are reported; a list is never `empty-menu`; the spec-v18 fixtures for them pass.
- [unit] The items: the focus history first, then windows it doesn't hold, front first; without the focused window; with the filters and `windows.apps` focus rules; at most `count`. `FocusHistory.limit` is at least 30, so 9 items survive filtering.
- [unit] Items are fixed when the list opens; when an item's window closes, the keys after it move up, and the highlight goes to the next item, else the one before, else Cancel.
- [self] Choosing a minimized window unminimizes and focuses it; a hidden app's window unhides it; the chosen window is first in the history before macOS reports the focus change, so two quick presses go A, B, A (against `FakeWindowSystem`).
- [self] In a held list, Cancel shows the focused window's title and icon; with no other window, only Cancel, and letting go does nothing and plays no sound.
- [snap] `hud-recent`: items with their window titles and app icons, keys 1 to 9, and marks for minimized, hidden, another Space and another display.
- [manual] Two apps on two Spaces, each focused once: CAG+H 1 goes to the other Space and back. A window on another Space that never had focus isn't listed. A held list on a menu that isn't held works by number keys.
UX:
- Glossary: "Recent Windows", "Cancel". A window with no title shows its app's name.
- Titles come from Accessibility (`kAXTitle`), never `kCGWindowName`, so no Screen Recording.
- The starter config doesn't add a list. The user's own CAG+H becomes one by hand, or in S-094.
- Marks are the row's note: "minimized", "hidden", "on another Space", "on another display", and "on another Space and display" for both. Cancel keeps its ✕ and shows the window in front beside it; VoiceOver says "Cancel, <title>". A list that isn't held with no items says "No recent windows".
Status: done
Verified: the list's fields, rules and the 9 spec-v18 fixtures (none pending now), the item order (`RecentWindows.items`), filling with keys pressed meanwhile replayed, closed items leaving with the highlight moving on, at most 9 items until S-093 (unit, 318 tests); against `FakeWindowSystem`: the order, Cancel as the window in front, keys and icons, marks, a minimized and a hidden window brought back, back and forth with no focus change reported, the filters, a window closing while the list is up, and only Cancel with no sound (self-test, 254 checks); hud-recent in light and dark. A list asks the engine to wait while the app reads the windows on the main thread, and the keys pressed in that time are replayed, so a fast CAG+H 2 works. Not yet tried by hand: the manual line, and how long reading every app's windows takes with many apps open.

### S-093 Page through more than 9 recent windows with More
As the user, with more than 9 windows in Recent Windows, I press 0 for More to see the next 9, numbered 1 to 9 again, and the repeat key keeps going across pages.
Screens: hud-recent-more
Depends: S-092
Acceptance:
- [unit] Pages of 9; `0` is More on every page but the last; Back goes to the page before, and from the first page works as in any menu; in a held list, the repeat key and Down go from item 9 onto the next page, and after the last item to Cancel on the first page; the highlight never rests on More.
- [snap] `hud-recent-more`: the second page, with its path showing the page, and More as a key row, not an item.
- [self] A `count` of 20 lists 20 windows over three pages.
UX:
- Glossary: "More", not "Next" (Focus Next and Swap Next already have it).
- The path adds the page whenever a list has more than one: "Recent Windows › Page 2 of 3". In a held list, More and Back put the highlight on the page's first item. VoiceOver counts across pages: "Window 10, 10 of 20".
Status: done
Verified: pages, More, Back to the page before, the repeat key and Down across pages and on to Cancel, Shift back from Cancel to the last item, removal across pages, and paging in a list that isn't held (unit, 321 tests); 20 windows over three pages (self-test, 255 checks); hud-recent-more in light and dark. Not yet tried by hand.

### S-094 Turn on Hold and make a list in the Bindings tab
As the user, I switch Hold on for a leader and make a menu into Recent Windows in Settings' Bindings tab, with its options, and the Help page tells me how held menus work.
Screens: bindings-hold, bindings-list, help
Depends: S-090, S-092
Acceptance:
- [snap] `bindings-hold`: a Hold switch on a leader, with one line of help, and none on other menus or bindings.
- [snap] `bindings-list`: a menu with "Fills Itself" set to Recent Windows, its options (Count, Minimized, Hidden, Spaces, Displays), and no add-key button under it.
- [self] Hold and each list field save and undo; turning Hold on where a key equals its repeat key shows that error on the key, with a fix it can offer ("Change the key"), and doesn't save a config that won't load.
- [snap] The Help page has a short Held Menus section: hold, repeat key, Shift, let go, Cancel.
UX:
- Flow: select a leader → Hold to Choose on (undo with ⌘Z); select a menu with no keys under it → Contents: Recent Windows → its options show at once → each change saves, ⌘Z undoes.
- Surface: inline, in the editor pane's Form (each changes one value of the selected row).
- Hold to Choose: a switch in its own section, on leaders only. Footer: "Hold the modifiers to keep this leader's menus open. The key that opened a menu moves the highlight, Shift moves it back, and letting go chooses."
- Contents: a picker on menus, "Keys You Add" or "Recent Windows". "Fills Itself" is dropped: Contents names what's in the menu. With keys under it, Recent Windows is disabled and the footer says "Remove the keys under this menu to make it Recent Windows."
- Recent Windows options: "Up to 9 Windows" (a stepper, 1 to 99), "Include Minimized Windows", "Include Hidden Apps", Spaces "All Spaces" or "Current Space", Displays "All Displays" or "This Display". Footer: "The app fills this menu with the windows you used last, keys 1 to 9. With more, 0 goes to the next 9."
- Outline: a list's Action column says "Recent Windows", it has no disclosure triangle, and its right-click menu has no New Binding or New Menu; with it selected, New Binding adds next to it.
- Errors: recording a key that's the held menu's repeat key is refused in the recorder: "D moves the highlight in this held menu. Choose another key." Turning Hold on over such a key shows the error in the banner with a "Change the Key" link that starts the recorder on that row.
- Help: a "Held Menus" section, five short lines.
Status: done
Verified: Hold to Choose and every Recent Windows option save and undo; a repeat key is refused in the recorder; Hold over a repeat key shows the error unsaved, and its "Change the Key" fix records a new key for that row; a menu with keys under it can't become Recent Windows (self-test, 265 checks; unit, 322 tests); bindings-hold, bindings-list and help-held in light and dark, grid checks. The editor pane puts Hold and Contents before Icon so a list's options fit without scrolling. Not yet tried by hand: VoiceOver on the new controls.

### S-095 Swap with a window chosen from Recent Windows
As the user, I hold Alt+Cmd+Tab, pick a window from the list, and it trades places with the focused one, as Swap Window does, so I can rearrange windows without leaving the keyboard.
Screens: bindings-swap
Depends: S-092, spec v19
Acceptance:
- [unit] `"choose": "swap"` reads and writes, `focus` is left out as the default; another value is `bad-list-value`; `minimized`, `hidden` or `spaces` with swap is `conflicting-fields`; the v19 fixtures pass.
- [self] A list that swaps holds only shown windows on the current Space, without apps left out of Swap Window; choosing trades frames and keeps focus; choosing again right away swaps back; a focused app left out of Swap Window fails with the alert.
- [snap] `bindings-swap`: When Chosen set to Swap, the focus-only options hidden, and a footer.
UX:
- Flow: select a Recent Windows menu → When Chosen: Swap → the options swap doesn't use go away → ⌘Z undoes.
- Surface: inline, in the Recent Windows section of the editor pane.
- Words: "When Chosen" with "Focus" or "Swap". Footer with Swap: "Choosing a window trades places with it, as Swap Window does, and focus stays. Only windows shown on the current Space are listed." Switching to Swap clears Minimized, Hidden and Spaces, since the file can't have them with it.
- Help: the Held Menus footer says a Recent Windows menu can swap instead.
Status: done
Verified: unit, 325 tests; self-test, 269 checks; bindings-swap in light and dark, grid checks. Not yet tried by hand: Alt+Cmd+Tab on real windows.

## Later
- Pick a window from an overlay: `"target": "pick"` on Focus Window and Swap Window labels the visible windows in order and waits for one key (numbers or home-row letters), Escape cancels.
- Import and export a single menu as a JSON snippet.
- A basic automatic tiling mode.
- Move a window to another display (Send to Space covers Spaces, S-096 and S-097); save and restore window layouts.
- New action families on the registry (S-060): volume, display resolution.
- Double-tap modifier leaders, such as tapping ⌥ twice.
- The green button fills a window instead of going full screen, as an option, with a per-app rule. Plan and risks: `docs/research/green-button-fill.md`. Put off: the button is rarely clicked.

## Dropped
Unnamed Manager's main jobs map to M1 and S-048 (job 1, run bindings), M11 (job 2, manage windows), M4 and S-070 (job 3, Bindings window), and S-002, S-008, S-009 and S-058 (job 4, menu bar status). The Windows app is its own repo, `unnamed-manager-windows`.

The launcher's main jobs mapped to M1 (job 1), M4 (job 2) and S-002, S-008 and S-009 (job 3). Rows marked "Version one? Yes" in the research matrix were written before the scope changed to leader keys only:
- **App launch:** covered by S-006.
- **Fuzzy and initials matching:** dropped. There's no search, and keys are exact.
- **Ranking that learns from your choices:** dropped. Order is set by you (S-028).
- **File search:** dropped. Spotlight covers it.
- **Action panel on results (⌘K):** dropped. There are no results to act on.
- **Act on selection (Instant Send):** dropped for version one.
- **Aliases and quick keys:** dropped. Key sequences replace them.
- **Per-item global hotkey:** covered by multiple leaders (S-001, S-003).
- **Calculator and units:** dropped.
- **Web search and quicklinks:** covered by `open` with a URL (S-010).
- **System commands:** covered by `exec` and `send` (S-011, S-012).
- **Run scripts and Shortcuts:** covered by `exec`, for example `shortcuts run "Name"` (S-011).
- **Accounts, sync, analytics, upgrade prompts:** dropped. This is a personal app.
- **A menu that also runs an action** (from LeaderTray, 2026-11-11): pressing Hyper+B would focus the browser and then open a menu of browser keys. Rejected: it saves one key press but changes the rule that an entry is a menu or a binding, which touches the config, the validator, the engine, the Bindings editor and the Guide.

### S-046 Use Application with Focus, Start, or Focus or Start
As the user, I choose whether an app binding only focuses the app, starts a new copy, or focuses it and starts it if needed. Open App is now Use Application, Choose by App is now Context Aware, and the Type picker is alphabetical.
Screens: actions-light.png, actions-dark.png
Depends: S-006, S-030
Acceptance:
- [unit] `mode` is `focusOrStart` (default, left out of the file), `focus` or `start`; an unknown mode is an error; the schema lists all three.
- [unit] Each mode plans its own way in: open, focus only, new copy.
- [self] Focus on an app that isn't running fails with "<App> isn't running." in the Guide.
- [self] The Type picker lists Context Aware, Do Nothing, Open, Run Command, Send Shortcut, Use Application.
- [snap] The Actions page shows a Mode picker under Bundle ID, with a footer for the mode.
Status: done
Verified: modes, file reading and writing, schema (unit tests); plans, Focus failure, Type order (self-test); Mode picker in light and dark (snapshots actions-app-*). Not yet tried by hand: Start on a running app opening a second copy.

### S-047 Focus returns to the last focused window
As the user, I press a Use Application binding for an app that's running and land in the window I used last, not whichever of its windows happens to be on top.
Screens: none (no UI)
Depends: S-046
Acceptance:
- [unit] The focused window wins, then the main window, then the frontmost standard window, then a minimized one; panels are skipped; no windows means nothing to raise.
- [self] A process that doesn't answer gives up within a second, and activation still runs.
- [manual] With two Ghostty windows, use the second, switch to another app, press Hyper+Space T: the second window is in front.
Status: done
Verified: window choice (unit tests), unresponsive process (self-test). Not yet tried by hand: the manual line; windows on another Space or under a window manager.

### S-048 Run an action straight from a chord
As the user, I give a top-level chord such as Hyper+T an action, and pressing it runs the action at once, with no menu and no Guide.
Screens: bindings-direct-light.png, bindings-direct-dark.png, empty-bindings-light.png
Depends: S-003, S-024
Acceptance:
- [unit] A top-level entry with an action loads as a direct binding; nothing can go under it.
- [unit] Its chord runs the action for the app in front and starts no sequence; holding it runs once; inside a sequence it's a key that isn't bound.
- [unit] A Context Aware direct binding with nothing to run for the app in front lets the chord through to that app.
- [self] New Binding with nothing selected adds a direct binding, which is saved once it has an action and runs from its chord.
- [snap] A selected direct binding says what it is under its key.
- [manual] Bind Hyper+T to Terminal, press it in another app: Terminal comes forward and no Guide appears.
UX:
- Flow: New Binding (⌘N) with nothing selected, or the empty state's New Binding → key recorder → choose an action → saved
- Surface: a top-level row in the Bindings outline (same as a leader)
- Words: "Direct binding"; footer "A direct binding is a chord that runs its action from anywhere, with no menu."
Status: done
Verified: unit tests, self-test, snapshots. Not yet tried by hand: the manual line.

### S-049 Write Meh, CAG, Opt and ⌃⌥⇧⌘ chords
As the user, I write `Meh+W` (⌃⌥⇧) or `CAG+T` (⌃⌥⌘) in the config file, or record those modifiers in the Bindings window, and the app reads and shows them by those names, as it does Hyper.
Screens: bindings-light.png, bindings-direct-light.png
Depends: S-025
Acceptance:
- [unit] `Meh` and `CAG` parse in any case; exactly those modifiers print as `Meh+…` and `CAG+…`; a group plus the missing modifier prints as `Hyper`.
- [unit] The JSON Schema accepts Meh and CAG chords.
- [unit] `Opt`, `Option`, `Control` and `Command` parse, and so do the symbols ⌃⌥⇧⌘, joined with + or right before the key (`⌃⌥⇧T`, `⌘+F`); the app writes names.
- [self] A key recorded with ⌃⌥⇧ or ⌃⌥⌘ is saved to the file as `Meh+…` or `CAG+…`.
- [snap] The outline and the key recorder show `Meh+W` and `CAG+T`.
Status: done

## Home

### S-050 Go Back to Home
As the user, I press Back in a leader's menu and see Home: every leader and direct binding, with the ones on my current modifiers at the top, so I can switch leaders or run a direct binding without starting over.
Screens: hud-home, hud-home-wide
Depends: S-007, S-048, S-049
Acceptance:
- [unit] With two or more top-level entries, Back in a leader's menu opens Home; with one, it ends the sequence.
- [unit] Back or Cancel in Home ends the sequence.
- [unit] Home groups top-level entries by exact modifiers, with the group of the leader you came from first, then the others in order of their first entry; rows keep file order.
- [unit] In the current group the key alone picks, with some, all or none of its modifiers held; other entries need their exact chord, counting held modifiers; a bare key prefers the current group; anything else is unbound.
- [unit] Picking a leader opens its menu; picking a direct binding runs it for the app that was in front when the sequence started.
- [unit] An unavailable Context Aware direct binding flashes and stays in Home.
- [self] Home's Guide lists the groups in order, and a wide Home never splits a group.
- [snap] Home with 12 rows or fewer: the current group, a horizontal separator, then each other group under its header.
- [snap] Home with more rows: groups side by side, no group split, a vertical divider after the current group.
UX:
- Flow: leader → its menu → Back → Home → a key or chord → that leader's menu, or the direct binding runs.
- Surface: the Guide (S-005).
- States: normal; wide (side by side); a disabled row reads "not available in <App>" (S-013).
- Words: path "Home", then "Home › Commands" after picking a leader. Group headers use the chord names the app writes: "Hyper", "Meh", "CAG", "Cmd", and "No modifiers". Keycaps show the key alone.
- Access: VoiceOver announces "Home, N keys" and each group header as a heading.
Status: done
Verified: engine and grouping (unit tests, HomeTests), groups, columns and dimmed rows (self-test), hud-home and hud-home-wide in light and dark (snapshots). Tried by hand on 2026-11-11: Back to Home and picking another leader with the real keyboard. Not yet tried by hand: VoiceOver reading the group headers.

## Help

A starting point when you're stuck, and a way to tell which build you're running.

### S-051 See the version in the menu bar menu
As the user, I open the menu bar menu and see which version is running, and for a build I made myself, which branch and commit it came from.
Screens: none (the menu bar menu isn't captured)
Depends: S-008
Acceptance:
- [self] A release shows "Version 0.1.3": the version alone.
- [self] A local build (no `APP_VERSION`) shows "Version 0.1 (branch, commit)", with ", modified" when the working tree had changes.
- [manual] The line sits above Quit, dimmed, and can't be clicked. The config line ("Config loaded at 14:02") is right under it.
UX:
- Surface: a disabled item in the menu bar menu, above Quit.
- Words: "Version 0.1.3"; "Version 0.1 (main, aa45720)".
Status: done
Verified: the line's text (self-test), the branch and commit in a local build's Info.plist. Not yet tried by hand: the manual line.

### S-052 Find my keys and how sequences work on the Help page
As the user, when I'm stuck I open Help and see my leaders and direct bindings, the keys that work in every sequence, what the words mean, and where to read more.
Screens: help, empty-help
Depends: S-050, S-051
Acceptance:
- [self] The page lists every leader and direct binding, grouped by modifiers as Home groups them, with the group of the first entry first.
- [self] It names your Cancel and Back keys, and says Back opens Home only when there are two or more top-level entries.
- [self] With no bindings it shows No Bindings with New Binding, and the rest of the page.
- [self] Help is a page of the Bindings window, in the sidebar and as ⌘4.
- [snap] Each row shows its key, title, and "Leader" or "Direct binding"; In a Sequence, Words, and More (Open Config File, the documentation, Report a Problem, and the version line) follow.
- [manual] Clicking a row shows it selected on the Bindings page (tried by hand on 2026-11-11). Help in the menu bar menu and Unnamed Launcher Help in the Help menu open the page. Neither has ⌘?, which macOS keeps for the Help menu's search.
UX:
- Flow: Help in the menu bar menu, or a Show Help chord (S-053), → the Bindings window on Help → click a row → the Bindings page with that row selected.
- Surface: a sidebar page of the Bindings window; a grouped Form, centered, at most 640 pt wide.
- States: with bindings; no bindings (No Bindings, New Binding); an invalid draft shows the last valid config.
- Words: "Your Keys: Hyper", "In a Sequence", "Words", "More", "Read the Documentation on GitHub", "Report a Problem".
- Access: each key row reads as "key, title, leader" or "direct binding" and is a button.
Status: done
Verified: content and page switching (self-test), help and empty-help in light and dark (snapshots), grid checks. Not yet tried by hand: the manual line.

### S-053 Show Help from a key
As the user, I press a chord such as Hyper+H, or a key in a menu, and the Help page opens in front, so I can find my keys when I'm stuck.
Screens: actions-help, hud-home
Depends: S-048, S-052
Acceptance:
- [unit] `{ "type": "help" }` loads as Show Help, takes no other fields, is written back unchanged, and plans opening the Help page.
- [unit] A Show Help direct binding runs from its chord and starts no sequence.
- [self] The starter config has Show Help on Hyper+H.
- [self] Show Help is in the Actions page's Type picker, in alphabetical order.
- [self] Running it opens the Bindings window on the Help page.
- [snap] A Show Help action's form says what it does and has no fields.
- [unit] Hyper+Comma, Hyper+Period and Hyper+Slash are rejected as leaders and direct bindings, and the key recorder refuses them: macOS keeps them for sysdiagnose.
- [manual] Press Hyper+H in another app: the Help page comes forward with focus; ⌘W closes it and the app you were in comes back.
UX:
- Flow: chord or key → the sequence ends → the Bindings window opens on Help, in front.
- Surface: the Help page (S-052). The action is set up on the Actions page like any other.
- Words: "Show Help"; form text "Opens the Help page of the Bindings window, which lists your leaders and direct bindings."
Status: done
Verified: loading, writing, the plan, the direct binding and the chords macOS keeps (unit tests); the starter, the picker, opening the page with the window closed (self-test); actions-help in light and dark (snapshots); Tried by hand on 2026-11-11: Hyper+H from Zed brings the Help page to the front with focus, and ⌘W gives focus back to Zed; Hyper+Slash never reached the launcher, which led to the sysdiagnose rule.
