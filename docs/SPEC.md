# Unnamed Manager: behavior and config spec

This is the source of truth for how sequences, actions and the config file behave. [BRIEF.md](BRIEF.md) says what the app is, and this file says how it works.

## How it works

### Bindings form a tree
- **Each config has one or more leaders.** A leader is a global chord, such as Hyper+Space, and opens a top-level menu.
- **Every entry is either a menu or a binding.** A menu has children and no action. A binding has an action and no children.
- **A top-level entry with an action is a direct binding.** Its chord, such as Hyper+T, runs the action at once: no sequence starts and the HUD never appears. Leaders and direct bindings can be mixed in one config, and a config can have only direct bindings.
- **Each key press is decided as soon as it arrives.** Which entry a key selects never depends on a timer, so there are no ambiguous prefixes.
- **There's no depth limit.** Two or three levels below the leader is typical.
- **Children are listed in config file order**, so you choose the order. The Bindings window has a "Sort Alphabetically" command for a menu. It rewrites that menu's children in three groups: named keys such as `Space` and `Tab` alphabetically (F-keys by number), then digits, then letters.

### During a sequence
| Key | Result |
| --- | --- |
| Leader chord | Opens its menu. The leader is consumed, so the app in front never sees it. |
| A child menu's key | Opens that menu. |
| A child binding's key | Runs the action and ends the sequence. |
| A direct binding's chord | Has no special meaning inside a sequence. It's a key that isn't bound. |
| Back (default Backspace) | Goes to the parent menu. In a leader's menu it opens Home, or ends the sequence when Home isn't shown (see Home). In Home it ends the sequence. |
| Cancel (default Escape) | Ends the sequence and runs nothing. |
| Any other key | Error feedback: the HUD flashes and/or the alert sound plays. The sequence stays where it is, and if the HUD was waiting for its delay, it appears now. |

- **Every key is consumed until the sequence ends.** That includes repeats and the key-ups of consumed keys. Outside a sequence, only leader chords and direct binding chords are consumed.

### Direct bindings
| Key | Result |
| --- | --- |
| A direct binding's chord | Runs the action for the app in front, and is consumed, along with its repeats and key-up. Holding the chord runs the action once. |
| The same chord when its Context Aware action has nothing to run for the app in front | Isn't consumed. The app in front gets the chord as if the launcher weren't running. |

- **Step keys have no modifiers.** Modifiers that belong to the leader and are still held are ignored, so you can press Hyper+W then 1 whether or not you've let go of Hyper. A step pressed with any other modifier doesn't match.
- **Keys mean physical positions on the US ANSI layout.** Other keyboard layouts don't change which key a name refers to.

### Home
Home is the menu above the leaders. It lists every leader and direct binding, so Back can go one level further up than a leader's menu. The global Cancel and Back keys stay as they are.

- **Opening it:** Back in a leader's menu opens Home. No chord opens it directly.
- **When it's shown:** only when the config has two or more top-level entries. With one, Back in the leader's menu ends the sequence, as before.
- **Leaving it:** Back or Cancel in Home ends the sequence.
- **Groups:** Home lists top-level entries in groups by their exact modifiers (Hyper, Meh, CAG, Cmd, no modifiers…), each under a header with its name. Rows show the key alone. Within a group every key is unique, because two entries can't share a chord, so grouping removes clashes like `Hyper+Space` and `Meh+Space`.
- **Current group first:** the group of the leader you came from comes first, then a separator, then the other groups in order of their first entry in the file. Within a group, rows are in file order.
- **Picking:** in the current group, press the key alone, with some, all or none of that group's modifiers held. Any other entry needs its exact chord, counting modifiers still held from the leader. When both could match, the exact chord wins, except for a key pressed with no modifiers: that picks from the current group first, so a bare-key entry such as `F13` is picked from Home only when the current group has no F13. Anything else is a key that isn't bound.
- **Leaders and direct bindings:** picking a leader opens its menu, and picking a direct binding runs it and ends the sequence. The app in front stays the one from when the sequence started.
- **Unavailable direct bindings:** a Context Aware direct binding with nothing to run for the app in front is shown disabled. Picking it flashes and stays in Home, as for any unavailable binding.
- **Layout:** when Home fits in one column (12 rows or fewer), the separator is a horizontal line. Otherwise the groups sit side by side: the current group in the first column, the others in more columns, never splitting a group, with a vertical divider after the current group.

### HUD
- **Delay:** `hudDelayMs` (default 0) is how long the sequence must sit idle before the HUD appears. Every key press restarts the delay. Once the HUD is shown, it stays until the sequence ends. If you know the sequence, nothing appears on screen.
- **Timeout:** `timeoutMs` (default 0, meaning off) ends the sequence after that long with the HUD visible and no key pressed. The timeout doesn't run while the HUD is still waiting for its delay, or when `showHud` is false.
- **Contents:** the HUD shows breadcrumbs (leader › menu › …) and the available keys with their titles. Contextual bindings that don't apply to the app in front are shown disabled.
- **Placement:** on the display of the app in front, at `position` (center, top or bottom).
- **Focus:** the HUD is a non-activating panel that never becomes the key window, so the app that was in front when the leader was pressed stays in front.

### Actions
| Type | Fields | Behavior |
| --- | --- | --- |
| `application` | `bundleId`, `mode` (optional) | `focusOrStart` (default) brings the app forward if it's running, otherwise starts it. `focus` only brings it forward if it's running. `start` starts a new copy even if one is running. Focusing a running app returns to its last focused window (through Accessibility), coming out of the Dock if it's the only one. |
| `open` | `target` | Opens a file, folder or URL with its default app. A leading `~` expands to the home folder. |
| `exec` | `command` (array), optional `cwd`, `env` | Runs a process directly, with no shell and no expansion except a leading `~`. `cwd` defaults to the home folder. The app doesn't wait for it or capture its output, but does report if it fails to start. |
| `send` | `keys` | Sends one or more chords to the app that was in front. Held leader modifiers must not leak into the chord. `Primary` means ⌘. |
| `contextual` | `variants` (context id → action), optional `fallback` | Uses the first context, in config order, that matches the app in front and has a variant. If none matches, uses `fallback`. With no fallback, the action is unavailable. |
| `noop` | none | Does nothing. |
| `help` | none | Opens the Bindings window on its Help page and brings it in front with focus, through NSWorkspace as for Use Application, since a chord doesn't make the launcher the active app. The sequence ends, as for any action. |

When an action fails, for example because the app isn't installed or the command can't start, the sequence ends and the failure is shown in the HUD and the log.

### Permissions and lifecycle
- **Required permissions:** Accessibility and Input Monitoring. Without both, the app installs no event tap, its menu bar icon shows a warning, and the menu names the missing permission with a button that opens the right pane in System Settings. If macOS needs a relaunch before a new grant takes effect, the menu offers one.
- **Event tap:** a session-level `CGEventTap`. The callback decides synchronously and must never block. If macOS turns the tap off, the app turns it back on and logs that it happened.
- **Secure Event Input:** while it's on, for example in a password field, keys don't arrive. The menu bar menu says so when it can detect it.
- **Disable:** turning the app off from the menu bar removes the tap, so no keys are captured.

## Config file

`~/.config/unnamed-manager/config.json`. A dotfiles tool such as chezmoi may write this file and overwrite edits made in the app, which is fine. The app watches the file and reloads it when it changes. A reload with errors keeps the last valid config and reports the error. The Bindings window and Settings write the same file with keys in a stable order.

```json
{
  "version": 1,
  "runtime": { "cancelKey": "Escape", "backKey": "Backspace", "showHud": true, "hudDelayMs": 500, "timeoutMs": 5000 },
  "ui": { "theme": "system", "position": "center", "errorFlash": true, "errorBell": true },
  "entries": [
    { "keys": "Hyper+Space", "title": "Commands" },
    { "keys": "Hyper+Space E", "title": "Editor", "action": "open-editor" },
    { "keys": "Hyper+Space A", "title": "Applications" },
    { "keys": "Hyper+Space A T", "title": "Terminal", "action": "open-terminal" },
    { "keys": "Hyper+Space F", "title": "Find", "action": "search" }
  ],
  "actions": {
    "open-editor":   { "type": "application", "bundleId": "dev.zed.Zed" },
    "open-terminal": { "type": "application", "bundleId": "com.mitchellh.ghostty" },
    "search": {
      "type": "contextual",
      "variants": { "browser": { "type": "send", "keys": "Primary+L" } },
      "fallback": { "type": "send", "keys": "Primary+F" }
    }
  },
  "contexts": [
    { "id": "browser", "apps": ["com.google.Chrome", "org.mozilla.firefox"] }
  ]
}
```

- **Entries are a flat, ordered list keyed by their full path.** Each entry can be read and diffed on its own, duplicates and orphans are easy to report, and every depth uses the same shape.
- **Key syntax:** tokens are separated by spaces. The first token is a chord, `Mod+…+Key`. Modifiers are `Ctrl` or `Control` (⌃), `Alt`, `Opt` or `Option` (⌥), `Shift` (⇧), and `Cmd`, `Command` or `Primary` (⌘), plus three names for groups: `Hyper` (⌃⌥⇧⌘), `Meh` (⌃⌥⇧) and `CAG` (⌃⌥⌘). Names are case-insensitive, and a group can be combined with other modifiers (`Meh+Cmd` is `Hyper`). The app writes and shows a chord with exactly one group's modifiers by that group's name, so `Ctrl+Alt+Shift+T` becomes `Meh+T`. The symbols ⌃⌥⇧⌘ work too, joined with `+` or written straight before the key as macOS menus show them: `⌃⌥⇧T`, `⌘+F` and `Opt+⌘K` all parse. The app always writes names, not symbols.
- **Key names:** `A`–`Z`, `0`–`9`, `F1`–`F24`, `Space`, `Tab`, `Enter`, `Backspace`, `Delete`, `Escape`, the arrows, `Home`, `End`, `PageUp`, `PageDown`, `Grave`, `Minus`, `Equal`, `LeftBracket`, `RightBracket`, `Backslash`, `Semicolon`, `Quote`, `Comma`, `Period`, `Slash`.
- **Icons:** an entry's optional `icon` is an SF Symbol name (`"terminal"`), or a path starting with `/` or `~` for that file's Finder icon. Without one, a menu shows the app's glyph (the menu bar icon), Use Application its app's icon, and Open its file's, folder's, or URL app's icon; other entries show none. A name macOS doesn't have shows no icon (S-054 to S-056).
- **Defaults:** only `version` and at least one entry are required. Everything else has a default.
- **Why JSON:** `Codable` reads and writes it with no dependency, arrays keep their order, and a JSON Schema gives editors validation. The app writes `config.schema.json` next to the config at launch, and the starter config's `"$schema": "./config.schema.json"` line points at it. The cost is that JSON has no comments.

### Validation
A config is rejected if any of these are true:
- `version` is missing or unsupported.
- There's an unknown field, a missing `title`, or `keys` that can't be parsed.
- Two entries have the same path (compared case-insensitively).
- An entry has no parent entry, or its parent is a binding.
- A menu has no children. (A top-level entry with an action is a direct binding, not an error.)
- A step key has modifiers, or is the cancel or back key.
- The cancel and back keys are the same.
- A leader or direct binding is Hyper+Comma, Hyper+Period or Hyper+Slash. macOS keeps these for its diagnostics (sysdiagnose) and takes them before any event tap, so the launcher would never see them. The key recorder refuses them too.
- A delay is negative.
- A binding names an undefined action.
- An action has the wrong fields for its type.
- A variant names an undefined context or is itself contextual.
- Two contexts share an `id`.

Actions or contexts that nothing uses produce a warning, not an error.

## Gotchas
- **The event tap callback must stay fast.** macOS turns off slow taps. The sequence engine has to be a small pure state machine (key events and timer fires in, decisions out) that has no AppKit dependency and can be fully unit-tested.
- **Held leader modifiers leak into `send`.** When sending a chord, set its flags explicitly rather than inheriting the current modifier state.
- **The HUD must never take focus.** Use an `NSPanel` with `.nonactivatingPanel` that doesn't become key. Keys come from the tap, not from the panel.
