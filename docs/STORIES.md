# Unnamed Manager: stories

Built from [BRIEF.md](BRIEF.md), [SPEC.md](SPEC.md), the shared spec in [../spec/CONFIG-SPEC.md](../spec/CONFIG-SPEC.md) and [research/launchers.md](research/launchers.md). M1 to M8 and the stories after `## Dropped` are Unnamed Launcher's, all done. Unnamed Manager's version one is M9 to M11. There is no reference app, so `Screens:` names the snapshot pages that show each story.

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
| `bindings` | The Bindings page of the Bindings window |
| `actions` | The Actions page |
| `contexts` | The Contexts page |
| `help`, `empty-help` | The Help page, with and without bindings |
| `actions-help` | The Actions page with a Show Help action |
| `actions-window` | The Actions page with each window action's form |
| `hud-window` | The Guide on a Windows menu with every window action |
| `settings` | The Settings window |

**How each acceptance line is checked:** `[snap]` snapshot, `[unit]` unit test, `[self]` self-test, `[manual]` a person must try it.

**Seed data:** snapshot mode loads a fixture config with two leaders, a nested menu, actions of every type, and two contexts. From S-070 it also has a Windows menu with one binding of each window action. Each of these can be created in the Bindings window or Settings (S-024 to S-032).

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
Verified: targets, bundle id, config path and no old name in the sources (unit tests, AppNameTests, ConfigLocationTests); 122 self-test checks; welcome, help and settings in light and dark (snapshots), grid checks. The signing certificate keeps its name, "Unnamed Launcher Code Signing", so the release secrets still work. Not yet tried by hand: granting the permissions to the new bundle id; a release through the renamed cask (it waits for the first v0.3.0 tag).

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
Status: todo

### S-067 Resize the window by a step or to an exact size
As the user, I make the window bigger or smaller by a set amount, or set it to an exact fraction of the screen, keeping one corner or the center in place.
Screens: none (no UI)
Depends: S-064
Acceptance:
- [unit] `by` changes width and height by points; `to` sets them as fractions of the usable area.
- [unit] The anchor (a corner, an edge or the center) stays where it was; the default anchor is the top-left corner.
- [unit] The result is clamped to the usable area.
- [self] A fake window with a fixed size reports no failure and stays as it was.
Status: todo

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
Status: todo

### S-069 Focus the next or previous window
As the user, I press a key to go to the next window, and another to go back, in a fixed order I can predict.
Screens: none (no UI)
Depends: S-068
Acceptance:
- [unit] The order is by display, left to right, then by window center, top to bottom and left to right; it wraps at the ends.
- [unit] The same set of windows always gives the same order, whatever was focused last.
- [self] With fake windows, next from the last window goes to the first.
Status: todo

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
Status: todo

## Later
- Import and export a single menu as a JSON snippet.
- A basic automatic tiling mode.
- Move a window to another display or Space; save and restore window layouts.
- New action families on the registry (S-060): volume, display resolution.
- A Windows menu in the starter config.
- Double-tap modifier leaders, such as tapping ⌥ twice.

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
