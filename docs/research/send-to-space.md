# Send to Space

Research for Unnamed Manager. Done 2026-11-18.
[V] verified in a source or on this Mac, [K] from knowledge, [U] unverified, test first.

Question: can a binding such as `CAG+Quote 2` put the focused window on
Space 2 on macOS with SIP on, and how? Decision it informs: whether to add
a Spaces action that moves a window, which technique it uses, and what it
falls back to.

## Findings

- **No public API.** macOS has no shortcut or API to move a window to
  another Space; Apple's own ways are dragging in Mission Control, dragging
  to the screen edge, and Dock › Options › Assign To for a whole app
  [V](https://trymainspring.com/blog/move-window-to-another-desktop-mac).
- **The old private calls are dead with SIP on.**
  `SLSMoveWindowsToManagedSpace` and the Sonoma 14.5 workaround
  (`SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace`) return normally
  but leave the window where it is on macOS 15 and 26
  [V](https://shiftplus.app/blog/macos-spaces-without-disabling-sip/),
  and Hammerspoon's `moveWindowToSpace` returned true without moving on
  27.0.1 [V](https://github.com/Hammerspoon/hammerspoon/issues/3903).
- **The bridged operation works today.** Since Tahoe, SkyLight has a class
  `SLSBridgedMoveWindowsToManagedSpaceOperation`
  (`initWithWindows:spaceID:`) that is submitted to WindowManager by a
  non-exported function, `SLSPerformAsynchronousBridgedWindowManagementOperation`,
  found by walking SkyLight's symbol table in memory. Hammerspoon PR #3889
  uses it with SIP on, tested on 26.5 and 26.6.2; a user reports it works
  on 27 [V](https://github.com/Hammerspoon/hammerspoon/pull/3889).
  InstantSpaceSwitcher uses the same family of bridged operations to move a
  dragged window and to make a Space current with no slide (PR #110)
  [V](https://github.com/jurplel/InstantSpaceSwitcher/issues/29).
- **Probe on this Mac, macOS 27.2.1 (26B131), SIP on:** the class exists,
  the symbol is in SkyLight's table (33,313 entries), and a submitted
  operation moved the probe's own window *and another process's window*
  from Space 1 to the second Space within 0.5 s, with no Space switch and
  no Accessibility prompt [V, probe].
- **It may already be closing.** On macOS 27.3 beta 2 (26C5047e)
  WindowManager logs "Rejecting bridged window management operation
  SLSBridgedMoveWindowsToManagedSpaceOperation from (pid) yabai" and the
  window stays; the only route left there goes through the Dock's
  connection, which needs SIP partly off
  [V](https://github.com/asmvik/yabai/issues/2853). One report, one beta,
  filed today.
- **The drag fallback.** Holding a window's title bar and pressing the
  macOS "Switch to Desktop N" shortcut carries the window along; Amethyst
  sends a window to Space N this way and needs `Ctrl+N` turned on
  [V](https://github.com/ianyh/Amethyst). Amethyst's version misbehaved on
  Sequoia (window vanished and came back), while holding the title bar by
  hand and pressing the shortcut still worked
  [V](https://github2.scsujunhua.workers.dev/ianyh/Amethyst/issues/1676).
  The Dock ignores synthetic DockSwipe events while a mouse button is held,
  so our quick switch can't carry a window; the native shortcut can
  [V](https://github.com/jurplel/InstantSpaceSwitcher/issues/29). On this
  Mac `CAG+1` to `CAG+5` are the "Switch to Desktop N" shortcuts
  (symbolic hot keys 118–122, enabled) [V, defaults]. The drag moves the
  pointer, slides, and switches you to that Space [K].
- **Space ids.** `SLSCopyManagedDisplaySpaces` lists each display's Spaces
  in Mission Control order with their ids and types (0 = desktop, 4 =
  full screen) and the current one; it worked unchanged in the probe
  [V, probe]. Ids change across restarts, so a binding names a number,
  not an id [V](https://shiftplus.app/blog/macos-spaces-without-disabling-sip/).
- **Windows.** `IVirtualDesktopManager::MoveWindowToDesktop` only moves the
  caller's own windows
  [V](https://devblogs.microsoft.com/oldnewthing/20201123-00/?p=104476).
  Other apps' windows need the undocumented
  `IVirtualDesktopManagerInternal::MoveViewToDesktop`, whose GUIDs and
  vtable change between builds; VirtualDesktopAccessor tracks them (24H2
  26100.2605 and later)
  [V](https://github.com/Ciantic/VirtualDesktopAccessor).

## Other apps

| App | How it moves a window to a Space | With SIP on | Notes |
| --- | --- | --- | --- |
| yabai | Dock scripting addition; bridged move without it | Partly (bridged only) | Rejected on 27.3 beta 2 [V](https://github.com/asmvik/yabai/issues/2853) |
| Hammerspoon | Bridged move, then compat ID, then the classic call | Yes, PR not merged | [V](https://github.com/Hammerspoon/hammerspoon/pull/3889) |
| Amethyst | Simulated title-bar drag + `Ctrl+N` | Yes | Broken on Sequoia for some [V](https://github2.scsujunhua.workers.dev/ianyh/Amethyst/issues/1676) |
| AeroSpace | Doesn't use Spaces; hides windows off screen | Yes | Avoids the problem [K] |
| ShiftPlus | Switches Space, then relaunches the app there | Yes | Quits apps; not a window move [V](https://shiftplus.app/blog/macos-spaces-without-disabling-sip/) |
| DeskStag | "Carry" to the neighbouring desktop | Yes | Method not published [V](https://deskstag.com/blog/switch-between-desktops-mac) |

Patterns: every tool that moves one window with SIP on uses either a
private call that Apple keeps closing, or a simulated drag. Every tool
offers "send" (you stay) and most also "take" (you go with it).

## Decisions (proposed, for discussion)

1. **Build it on the bridged operation**, because it moved another app's
   window on this Mac with SIP on, quietly and with no slide [V, probe].
   Look the class and symbol up at run time; with either missing, use the
   fallback.
2. **Check the result.** The operation is asynchronous and returns success
   even when WindowManager rejects it (#2853), so read the window's Space
   back with `SLSCopySpacesForWindows` within about 0.5 s; if it didn't
   move, use the fallback. Planned test: a self-test step and the probe.
3. **Fallback: the title-bar drag with the macOS shortcut** for that
   Space, read from `com.apple.symbolichotkeys` (118 and up). When that
   shortcut is off, fail with a message that says to turn it on. Planned
   test: by hand first (hold a title bar, press `CAG+2`) on 27.2.1 [U].
4. **Target by number, plus `left` and `right`,** counting desktops only on
   the focused window's display, as the macOS `Ctrl+N` shortcuts do.
   Full-screen Spaces can't take a window [K]: sending to one is not
   possible, so numbers skip them. Planned test: confirm with a full-screen
   app between desktops [U].
5. **Focus after a send:** focus stays on the current Space, on the next
   window in the focus history there, so typing doesn't go to a window you
   can't see. Planned test: check where macOS leaves key focus after the
   move [U].
6. **Optional `follow`:** go to that Space too. The same bridged family
   can make a Space current with no slide (InstantSpaceSwitcher PR #110),
   which would also give Switch Space by number, now a Planned item in the
   spec [V](https://github.com/jurplel/InstantSpaceSwitcher/issues/29).
7. **Name: "Send to Space".** "Move" is taken (Move Window moves by
   points), and "Push" reads as a direction, as in pushing to the side.
   "Send" says the window goes and you stay; Windows' Task View says "Move
   to", so its UI name could be "Send to Desktop". A follow variant could
   be "Take to Space".

## Open questions

- Does the bridged move survive macOS 27.3? Watch yabai #2853; if it
  doesn't, the drag is the only route with SIP on [U].
- Does the drag fallback work on 27.2.1 with a synthetic mouse-down, or
  only by hand, as on Sequoia? [U]
- What happens with a window in a native tab group, a sheet, or a window
  set to "All Desktops" (Dock › Options)? [U]
- With Displays have separate Spaces on, can a window go to a Space on the
  other display? The probe only tried one display [U].
