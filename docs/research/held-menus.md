# Held menus and the recent-windows switcher

Research for Unnamed Manager. Done 2026-11-18.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

**Question:** how should a menu behave while its leader's modifiers are held, the way Alt+Tab and ⌘Tab do, and how do we build a menu of recently used windows?
**Decision it informs:** the interaction rules for spec v18 (shared with the Windows app), the config fields, and the macOS and Windows APIs the switcher uses.

## Already decided (with the user, 2026-11-18)

- This is the general case: any menu can work while held, and the recent-windows switcher is one use of it.
- Commit when the **first** of the chord's modifiers is released. Track the set of modifiers, not their order. kanata releases ⌃⌥⌘ in a burst, and the order can vary.
- The Guide's delay still applies. "CAG+H 2" typed quickly shows nothing. Use the Guide HUD; there is no separate panel.
- There is a highlight. Opening a menu highlights its first item. Pressing the key that opened the menu again (the repeat key) moves the highlight forward. Adding Shift moves it back, unless Shift is already in the chord.
- Direct picks move the highlight. Release commits it, consistently.
- Nested menus behave the same way. In "CAG+A B", B opens the Browser menu with its first item highlighted, and B becomes that menu's repeat key.
- A child key equal to its menu's repeat key is invalid. The validator rejects it. Today's "CAG+D D" (Center) has to move.
- Item 0 is Cancel. In the recent-windows menu, item 0 is the window in front, so going back to it changes nothing. Escape cancels too.
- The recent-windows menu has options per entry for including minimized and hidden windows, other Spaces and other displays. That lets you put different scopes on different chords. It respects `windows.apps`. At most 9 items by default.
- A rough config shape: `{ "keys": "CAG+H", "switcher": { "repeat": "H", "labels": "numbers", "count": 9 } }`.

## Findings

### Market
- **Four apps combine hold, release-to-commit and most-recent order:** ⌘Tab, Windows Alt+Tab, AltTab and Witch. The closest to "hold, type a label, release" is Contexts' Fast Search: hold Fn, type 1–2 letters, release. [V](https://contexts.co/)
- **⌘Tab switches apps, not windows.** ⌘\` cycles the front app's windows. [V](https://support.apple.com/en-us/102650)
- **Windows Alt+Tab:**
  - It switches windows in most-recent order. [V](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec)
  - Ctrl+Alt+Tab keeps it open after release. [V](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec)
  - Windows 11 settings can add Edge tabs (3, 5, 20 or none) and choose between this desktop and all desktops. [V](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-multitasking)
- **AltTab (lwouis):**
  - Free under GPL-3.0. v11.10.2 came out on 2026-11-16. [V](https://alt-tab.app/features)
  - Pro costs $9.99 and adds search and up to 9 shortcuts. [V](https://alt-tab.app/pricing)
  - It shows minimized, hidden and other-Space windows with a badge.
- **Witch:** $14, closed source. It can have several switchers, each with its own order, plus search and spring-loading. [V](https://manytricks.com/witch/)
- **rcmd:** hold right ⌘ and press an app's letter. Pressing the letter again cycles that app's windows. Closed source; Pro is €15. [V](https://lowtechguys.com/rcmd/)
- **cmdcmd:** two-letter sticky labels such as `gc` for Chrome. Extra windows of the same app get a home-row second letter (`gj`, `gk`). There's also a 1–9 mode. It's a pre-release. [V](https://github.com/peterp/cmdcmd)
- **Wingo:** numbers 1–9, in most-recent order. It's new and has no feedback yet. [V](https://github.com/okaryo/wingo)
- **FastWindowSwitcher (Windows):** the easiest home-row keys go to the most recent windows. Abandoned since 2017. [V](https://github.com/JochenBaier/fastwindowswitcher)
- **Switcheroo (Windows):** title search, and it can replace Alt+Tab. Stale since 2015. [V](https://github.com/kvakulo/Switcheroo)
- **Search is the paid tier** in both AltTab and rcmd, which shows users value it. [V](https://alt-tab.app/pricing)

### Interaction design
- **Pre-highlight:**
  - Alt+Tab and AltTab draw the current window first and highlight the second. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/SelectionResolverSpecs.md)
  - With only one window, AltTab highlights that one. If the current window is filtered out, it highlights the first tile. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/SelectionResolverSpecs.md)
  - This matches "item 0 is Cancel, the highlight starts on item 1".
- **The highlight follows the window, not the row:**
  - Until you first move it, AltTab works the highlight out again on every refresh. After that it follows the window's id.
  - If the highlighted window disappears, it moves to the next item, else the previous one.
  - It never commits to a neighbour while a redraw is pending.
  - Windows that appear after the press are skipped. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/SelectionResolverSpecs.md)
- **Panel delay:**
  - AltTab's "apparition delay" defaults to 100 ms, adjustable from 0 to 900 ms. It's a timer tied to its session, so a release before it fires never shows the panel. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/App.swift)
  - ⌘Tab and Alt+Tab both use a short fixed delay. [K]
  - which-key defaults to 1.0 s and warns against 0. Once the popup is up, it redraws at once on each key. [V](https://github.com/justbur/emacs-which-key)
- **Escape:** AltTab only takes Escape while its switcher is active. Two quick ⌥⇥ presses count as two sessions, and keys that arrive while it closes are discarded. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/events/KeyboardEventsSpecs.md)
- **⌘Tab extras:** Q quits, H hides, ↑/↓ shows the app's windows, and holding ⌥ on release restores minimized windows. [V](https://www.macrumors.com/how-to/macos-app-switcher-tips-hidden-tricks/) (third-party source)
- **AltTab's keys inside the switcher:** W closes, M minimizes, F fullscreen, Q quits, H hides, S searches. Arrow keys on, vim keys off, mouse hover off. On release it can do Focus, Hold or Search. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/preferences/Preferences.swift)
- **Alt+Tab extras:** Delete closes the highlighted window. [V](https://thewindowsclub.com/how-to-close-a-window-when-using-alt-tab-in-windows-11) (third-party source)

### macOS platform
- **Modifier release:**
  - Each modifier change arrives as a `flagsChanged` event. Compare the set of flags held; don't count events.
  - Device bits tell left from right (left ⌘ 0x08, right ⌘ 0x10). [V](https://opensource.apple.com/source/IOHIDFamily/IOHIDFamily-870.60.4/IOHIDSystem/IOKit/hidsystem/IOLLEvent.h.auto.html)
  - AltTab reads releases from flag state and keeps a log of them, so the order survives main-thread stalls. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/events/KeyboardEvents.swift)
  - The engine already receives `.flags` and tracks `heldLeaderModifiers` (`SequenceEngine.swift`).
- **Secure Input** blocks `keyDown` but not `flagsChanged`, according to a comment in AltTab's source. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/events/KeyboardEvents.swift)
- **When the event tap is disabled** by a timeout or user input, events during the gap are lost. [U]
  - `KeyCapture.swift` re-enables the tap already.
  - After re-enabling, and on a short timer while a held menu is open, read `CGEventSource.flagsState(.combinedSessionState)` so a lost release can't leave the menu stuck. [V](https://developer.apple.com/documentation/coregraphics/cgeventsource/flagsstate(_:)) [U] that it works without extra permission.
- **⌘Tab:**
  - The Dock claims ⌘⇥ in the WindowServer's symbolic-hotkey layer. AltTab turns it off with the private `CGSSetSymbolicHotKeyEnabled`, and the change outlives the app. [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/CGSSymbolicHotKey.swift)
  - There's no public way. Whether the event tap can swallow ⌘⇥ before the Dock sees it is [U].
- **Windows on other Spaces:**
  - `kAXWindows` lists current-Space windows only, and leaves out fullscreen ones. [V](https://www.hammerspoon.org/docs/hs.window.html) [V](https://developer.apple.com/forums/thread/121114)
  - AltTab reaches the others through private SkyLight and AX calls (`CGSCopyWindowsWithOptionsAndTags`, `_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken`). [V](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift)
  - **This app already does better than "current Space only" with public API.** Focus History keeps each window's AX element, and a saved element for a window on another Space still answers. AXRaise then activate moves to that Space. This was tried by hand on 2026-11-17 (S-083 in `STORIES.md`). The limit: a window on another Space that hasn't had focus since the app started isn't in the history.
- **The front-to-back order of `CGWindowListCopyWindowInfo` can lag** right after a focus change. [V](https://developer.apple.com/forums/thread/713113) Build the order from the app's own Focus History, not from that list.
- **Titles:**
  - `kCGWindowName` needs Screen Recording, and what gets redacted changed in the macOS 27 beta. [V](https://developer.apple.com/forums/thread/126860) [V](https://developer.apple.com/forums/thread/839069)
  - `kAXTitle` needs only Accessibility. [K]
  - App icons come from `NSRunningApplication.icon`. [K]
- **Minimized and hidden windows:**
  - AXRaise does nothing on a minimized window: set `kAXMinimized` to false first. [K]
  - Hidden apps: `unhide()`, or activating the app, shows them. [K]
  - For a hidden app, `kAXWindows` may list only its minimized windows. [V](https://lists.apple.com/archives/accessibility-dev/2003/Mar/msg00031.html) (2003) [U] on macOS 27.

### Windows platform
- **A low-level keyboard hook (`WH_KEYBOARD_LL`) can swallow Alt+Tab** by returning nonzero. Switcheroo does this, and commits on LeftAlt key-up. [V](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc) [V](https://github.com/kvakulo/Switcheroo/blob/master/Switcheroo/MainWindow.xaml.cs)
- **A slow hook is removed silently.** The timeout is capped at 1000 ms on Windows 10 1709 and later. Needs a message loop and a watchdog. [V](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc) [U] that a watchdog is enough.
- **Where the hook sees nothing:**
  - Elevated windows, unless the app is signed with `uiAccess`.
  - The secure desktop: UAC prompts and Ctrl+Alt+Del. [K]
- **Releasing Alt alone opens the menu bar** once the hook has swallowed the keys. Inject a mask key; AutoHotkey suggests vkE8. [V](https://www.autohotkey.com/docs/v2/lib/A_MenuMaskKey.htm)
- **`RegisterHotKey`** can't take Alt+Tab reliably and doesn't see key releases. [V](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)
- **Bringing a window forward:** `SetForegroundWindow` has rules about which process may do it. Because the hook took the last input, it mostly works. Switcheroo also simulates an Alt press. [V](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)
- **Recent-window order:** track `EVENT_SYSTEM_FOREGROUND` and seed the list from z-order at start.
- **Which windows count:** filter by owner, by `WS_EX_TOOLWINDOW`, and by `DWMWA_CLOAKED`, which marks windows on other virtual desktops. [V](https://devblogs.microsoft.com/oldnewthing/20071008-00/?p=24863) [V](https://devblogs.microsoft.com/oldnewthing/20200302-00/?p=103507)
- **Virtual desktops:**
  - `IVirtualDesktopManager` can only ask which desktop a window is on, or move this app's own windows. It can't list desktops or switch between them. [V](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager)
  - Whether activating a window on another desktop switches to it is [U].
- **Edge tabs** in Alt+Tab aren't real windows, so a replacement can't list them. [K]

## Likes and dislikes

| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| ⌘Tab | Instant, never lags. A quick tap toggles with no panel. Reliable across Spaces and full screen. | Apps, not windows. Picking a minimized or hidden app does nothing. Icons only. An occasional 0.5 s lag. | [HN](https://brianlovin.com/hn/36164938), [substack](https://charlesmoir.substack.com/p/alttab-and-why-macos-sucks), [MPU](https://talk.macpowerusers.com/t/is-command-tab-supposed-to-be-slow/26899) |
| Windows Alt+Tab | Windows, not apps, with thumbnails. Opens minimized windows. People who move to Mac miss it. | Edge tabs clutter the list and broke quick back-and-forth. Windows of the same app are hard to tell apart. | [winaero](https://winaero.com/how-to-disable-microsoft-edge-tabs-in-alttab-on-windows-11), [MS Q&A](https://learn.microsoft.com/en-us/answers/questions/2391021/unable-to-switch-between-edge-tabs-using-alt-tab) |
| AltTab | Free and open source. Lists windows, including minimized and hidden. Very configurable: apparition delay, release action. | Overshoot from its own key repeat (#3117, 98 👍). Screen Recording nags (#1082, #3973). Lag before the panel appears (#5177). A fast release fails to focus (#5881). Order not updated before the next tap (#5575). Gaps with other Spaces (#1324). | [#3117](https://github.com/lwouis/alt-tab-macos/issues/3117), [#1082](https://github.com/lwouis/alt-tab-macos/issues/1082), [#5177](https://github.com/lwouis/alt-tab-macos/issues/5177), [#5575](https://github.com/lwouis/alt-tab-macos/issues/5575), [#5881](https://github.com/lwouis/alt-tab-macos/issues/5881) |
| Witch | Tab search. Several switchers. Activates apps with no windows. | 3+ seconds to show with many windows. No previews of minimized windows. Confusing settings. Patchy Spaces support. | [HN](https://brianlovin.com/hn/36164938), [FAQ](https://manytricks.com/witch/help/qanda.html) |
| Contexts | ⌘+number picks. Learned search keywords. Hold-type-release. | No thumbnails or tabs. Stale since 2022. Called "slowest" [U]. | [contexts.co](https://contexts.co/), [MPU](https://talk.macpowerusers.com/t/contexts-reconsidered-charmstone-discovered/25686) |
| rcmd | Instant, no panel. Stable letters: "without looking". Letters you can set. | Same-letter collisions, only 26 letters, names starting with a digit. | [MPU](https://talk.macpowerusers.com/t/rcmd-fastest-app-switcher-to-date/30183), [lowtechguys](https://lowtechguys.com/rcmd/) |
| Wingo | Zero setup. 1–9 picks. | History lost when it quits. Fixed hotkey. No feedback yet. | [GitHub](https://github.com/okaryo/wingo) |
| cmdcmd | Mnemonic sticky labels. Clean collision handling. | Pre-release. Needs Screen Recording. Private APIs. | [GitHub](https://github.com/peterp/cmdcmd) |
| FastWindowSwitcher | One key reaches any window. Home-row keys go to recent windows. | Automatic letters can't be pinned [U]. Dormant. | [GitHub](https://github.com/JochenBaier/fastwindowswitcher) |
| Switcheroo | Fast title search. Replaces Alt+Tab. | Slow with many windows (#149). No number picks upstream. | [GitHub](https://github.com/kvakulo/Switcheroo/issues) |

**Patterns.**

What people like everywhere, so we must keep it:
- a quick tap that toggles with no panel;
- one item per window;
- picking a minimized or hidden window actually brings it back;
- stable labels for things you reach often.

What people dislike everywhere, which is our chance to do better:
- overshoot from key repeat;
- lag before the list appears;
- a fast release that gets lost;
- an order that's stale on the next tap;
- picks that silently do nothing;
- permission prompts.

Stable letters already exist here: they are your app bindings. So the recent-windows menu can use numbers that follow recency, where "1 is the window before" stays predictable.

## Feature matrix

| Feature | ⌘Tab | Alt+Tab | AltTab | Witch | rcmd | cmdcmd | Version one? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hold, release commits | yes | yes | yes | yes | yes | no | Yes, for any menu |
| Quick tap goes to the previous item, no panel | yes | yes | yes | yes | yes | no | Yes |
| Panel after a delay | fixed | fixed | 0–900 ms | yes | no panel | n/a | Yes (`hudDelayMs`) |
| Repeat key forward, Shift back | yes | yes | yes | yes | cycles | no | Yes |
| Direct pick by number or label | no | no | no | no | letters | letters or 1–9 | Yes (menu keys; numbers in the switcher) |
| Item 0 is Cancel, Escape cancels | Esc | Esc | Esc | Esc | n/a | Esc | Yes |
| Arrow keys move the highlight | yes | yes | yes | yes | no | yes | Yes [U] keep or drop |
| Windows, not apps | no | yes | yes | yes | both | yes | Yes |
| Minimized and hidden shown and restored | partly | yes | yes | partly | yes | yes | Yes, optional per entry |
| Other Spaces | apps only | desktops (setting) | private APIs | patchy | yes | private | Yes, windows used since launch |
| Other displays | yes | yes | yes | yes | yes | yes | Yes, optional per entry |
| Close, minimize or quit from the menu | Q, H | Delete | W, M, Q, H | H, M | no | no | No, later |
| Search while held | no | no | Pro | yes | Pro | ⌘F | No, later |
| Thumbnails | no | yes | yes | yes | Pro | yes | No (needs Screen Recording) |
| Take over the system chord | — | Windows: hook | private API | no | no | no | Windows only; macOS uses your own chord |

## Decisions

1. **Commit when the set of chord modifiers held stops being complete, not by counting events.** kanata's burst and hand-typed chords then behave the same way.
   - Because AltTab works from flag state ([V](https://github.com/lwouis/alt-tab-macos/blob/master/src/events/KeyboardEvents.swift)) and the release order varies.
   - Planned test: a unit test feeding ⌃⌥⌘ releases in all six orders; a manual test with kanata.
2. **Recover stuck modifiers.** On a tap re-enable, and every 100 ms or so while a held menu is open, read `flagsState`. If the chord is no longer held, commit.
   - Because missed releases are the risk AltTab guards against.
   - Planned test: the self-test disables the tap during a hold, then releases.
3. **Ignore key repeat for the repeat key.** One press moves the highlight one item.
   - Because overshoot from repeat is AltTab's top issue ([V #3117](https://github.com/lwouis/alt-tab-macos/issues/3117)). The engine already consumes `isRepeat`.
4. **Fix the item list when the menu opens.** The highlight follows the item. If the highlighted window disappears, it moves to the next item, else the previous one, else Cancel.
   - Because that's AltTab's rule ([V](https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/SelectionResolverSpecs.md)).
5. **Update Focus History as part of committing a pick, not when the focus notification arrives,** so the next quick tap sees the new order.
   - Because of [V #5575](https://github.com/lwouis/alt-tab-macos/issues/5575).
   - Planned test: two taps 50 ms apart go A→B→A.
6. **Commit a release that comes before the Guide is drawn.** Never wait on the window list: build the switcher's items from Focus History, which is already in memory.
   - Because lag and lost fast releases are the top complaints about AltTab and Witch ([V #5177](https://github.com/lwouis/alt-tab-macos/issues/5177), [V #5881](https://github.com/lwouis/alt-tab-macos/issues/5881)).
7. **Use the Guide HUD with a highlighted row.**
   - The existing `hudDelayMs` is the apparition delay, tied to its sequence.
   - Once the Guide is showing, nested menus appear at once.
   - Use `kAXTitle` for titles and app icons for the rest, so no Screen Recording is needed.
   - Because AltTab's Screen Recording requirement is a top complaint ([V #1082](https://github.com/lwouis/alt-tab-macos/issues/1082)).
8. **Restore what you pick.** Unminimize, then unhide or activate, then raise.
   - Because picks that do nothing are the top complaint about ⌘Tab ([V HN](https://brianlovin.com/hn/36164938)).
   - Planned test: the self-test picks a minimized window and a hidden app's window.
9. **Other Spaces come from Focus History, with public API only.**
   - The list is the windows used since the app started, plus the current Space's AX windows. Raise `FocusHistory.limit` from 10 to about 30, so 9 items survive filtering.
   - No private SkyLight calls in version one.
   - Because the saved AX element approach already works across Spaces (S-083, tried by hand). Private calls can break on any update ([V](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift)).
   - Planned test: a manual test with two apps on two Spaces.
10. **On macOS, use your own chord; don't take over ⌘Tab in version one.**
    - Because there's no public path, and the private disable outlives a crash ([V](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift)).
    - Planned test (for later): can a session event tap swallow ⌘⇥ before the Dock?
11. **On Windows, the spec allows replacing Alt+Tab, with stated limits:**
    - not over elevated windows without `uiAccess`;
    - never on the secure desktop;
    - a mask key on Alt release;
    - a hook watchdog.
    - Because of [V](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc) and [V](https://www.autohotkey.com/docs/v2/lib/A_MenuMaskKey.htm).
12. **Numbers in the switcher, with 0 as Cancel.** Elsewhere, stable letters: the keys you write in your menus.
    - Because users say recency order breaks muscle memory, while stable letters work "without looking" ([V](https://talk.macpowerusers.com/t/app-switching-by-typing-first-few-letters-of-app-name/32742), [V](https://talk.macpowerusers.com/t/rcmd-fastest-app-switcher-to-date/30183)).
    - With 2–3 windows, "1 is the one before" stays predictable.
13. **Considered, not taken: commit a direct pick on the key press.** Two tracks suggested it. You chose commit-on-release for consistency.
    - "CAG+H 2" then letting go is still a single motion, so the cost is near zero.

14. **Held menus are opt-in: `"hold": true` on a menu** (decided 2026-11-18). The switcher has it on by default. Menus without it work as today, so you can press `CAG+D`, let go, and then press a key. The rule that a child key can't equal its menu's repeat key applies only to held menus.
15. **↓ and ↑ move the highlight forward and back in a held menu, unless an item uses that key; then the item wins** (decided 2026-11-18). ← and → are unbound for now. A held arrow moves one item per press, like the repeat key.

## Open questions

- **Releasing on a highlighted submenu:**
  - (a) Opens it as an ordinary menu, so the sequence continues without modifiers.
  - (b) Cancels.
  - Recommended: (a).
- **What does a Cancel item mean in an ordinary menu?** Item 0 is drawn as "Cancel", and the first real item is highlighted.
- **Labels for more than 9 items** (letters after 9?). Or keep the cap at 9.
- **[U] Can `flagsState` be read without extra permission** from the event tap's thread, and is it current right after a tap re-enable?
- **[U] Does a hidden app's `kAXWindows` list only its minimized windows on macOS 27?** Test with TextEdit hidden.
- **[U] Does AXRaise plus activate switch Spaces** when the app also has a window on the current Space? S-083 tried two Safari windows; try two apps.
- **[U] Windows: does activating a window on another virtual desktop switch to that desktop?** Test on Windows 11 24H2.
