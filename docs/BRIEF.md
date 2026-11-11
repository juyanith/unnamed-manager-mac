# Unnamed Manager

A native macOS keyboard manager for one keyboard-first user. A hotkey or a leader sequence starts an app, opens a file, runs a command, sends a shortcut, or focuses, places, moves, resizes, maximizes or minimizes the window you're using. Actions are modules, so later ones (volume, display resolution) add a module and change nothing else.

App name `UnnamedManager`, display name "Unnamed Manager", bundle id `net.unnamed.manager`, repo `unnamed-manager-mac`. It grew out of Unnamed Launcher 0.2.0 and keeps its history. The config format is shared with the Windows app and defined in [spec/CONFIG-SPEC.md](../spec/CONFIG-SPEC.md). How sequences behave: [SPEC.md](SPEC.md).

## Replaces
- **Unnamed Launcher**, completely. Everything it does carries over unchanged.
- **A separate window manager** for one-shot window commands: focus by direction, size presets, maximize.

## Main jobs
1. **Run a binding by key sequence or direct chord.** Unchanged from the launcher: Hyper+Space → E opens the editor; the Guide appears only if you pause; the app in front keeps focus.
2. **Manage the window in front from the keyboard.** Focus the nearest window left, right, up or down, or the next or previous one. Place it on a half, third, quarter or corner of the screen. Move or resize it by a step or to an exact fraction. Maximize it (again restores) or minimize it.
3. **See and edit bindings in the Bindings window**, including the new window actions, each with its own editor. Every change is written back to the config file.
4. **Check status from the menu bar.** Unchanged: on or off, reload, permissions, last error, quit.

## Data
One JSON file, `~/.config/unnamed-manager/config.json`, in the shared format. On first run, if it's missing and `~/.config/unnamed-launcher/config.json` exists, the app offers to copy it.
- **One config per platform** (decided 2026-11-11): the Mac and Windows apps share the format and validation rules, not the file. Mac actions name apps by `bundleId`; contexts list bundle ids.
- **Entry, Action, Context, Settings:** as in the spec. New action types are `window.focus`, `window.place`, `window.move`, `window.resize`, `window.maximize` and `window.minimize`. Their fields are settled in the spec repo first, then built here.
- **Window memory:** the frame each window had before Maximize, kept in memory only, so Maximize can toggle back.

## Shape
A menu bar app with no Dock icon, as today: the Guide (a non-activating Liquid Glass panel), the menu bar menu, the Bindings window (sidebar: Bindings, Actions, Contexts, Help), and Settings. macOS 27 or later. Swift and SwiftUI. Local data, works offline, no accounts.

## System hooks
- The launcher's session-level `CGEventTap`, with **Accessibility** and **Input Monitoring**. No new permission: window actions use the Accessibility API (`AXUIElement` position, size, minimized, raise), which the app already has.
- **An action registry.** Each action family is one module: it decodes and validates its config, describes itself for the Guide and the editor, and runs. Adding a family touches no shell code.
- Each display's usable area comes from `NSScreen.visibleFrame` (without the menu bar and Dock). Directional focus works across displays.
- Login item via `SMAppService`. Not sandboxed, Developer ID and notarized, distributed by the Homebrew cask (renamed to `unnamed-manager`).

## Reference
None to clone. Window commands follow Rectangle's behavior; the sequences follow which-key style leader menus.

## Look
Native, with the system accent color, as the launcher is now. Window actions get SF Symbols in the Guide (`rectangle.lefthalf.filled` and the like).

## Not in version one
- **Automatic tiling.** A basic version may come later.
- **Moving windows between displays or Spaces**, and remembering layouts.
- **Volume, display resolution and other new families.** The registry makes room for them.
- **The Windows app.** It lives in `unnamed-manager-windows`, built with BAWA.
