# Glossary

One name per idea. Use these words in the UI, the docs, the log and VoiceOver labels.

| Term | Means | Not |
| --- | --- | --- |
| Leader | The global chord that starts a sequence, such as Hyper+Space. Each leader opens its own top-level menu. | trigger, hotkey, prefix, activator |
| Key | A single key pressed after the leader to pick a menu or binding (in the config, a "step key"). | step, shortcut, letter |
| Sequence | Everything from pressing a leader until a binding runs, you cancel, or it times out. | chord chain, session, combo |
| Menu | A named group of keys inside a sequence, such as Applications. It opens more choices and runs nothing itself. | folder, group, submenu, category |
| Binding | A key that runs an action, such as E → Editor. | shortcut, command, item, mapping, hotkey |
| Direct binding | A binding on a global chord, such as Hyper+T → Terminal. It runs at once, with no sequence and no guide. | hotkey, global shortcut, quick key |
| Home | The menu above the leaders, listing every leader and direct binding by group. Back from a leader's menu opens it. | root, top level, start menu, launcher menu |
| Group | In Home, the top-level entries that share the same modifiers, such as Hyper. | layer, modifier set, section |
| Entry | Config-file word for a menu or binding. Never shown in the UI; say "binding" or "menu". | (UI) |
| Action | What a binding does: open an app, open a file or URL, run a command, send a shortcut, choose by app, or nothing. | command, task, handler |
| Use Application | The `application` action: focus an app, start it, or both, by its mode. | Open App, launch, activate, switch to |
| Focus or Start | The default mode of Use Application: bring the app forward, starting it first if it isn't running. | open, launch or activate |
| Focus | A mode of Use Application: bring the app forward only if it's running. | activate, switch to |
| Start | A mode of Use Application: start a new copy of the app, even if one is running. | launch, open, new instance |
| Open | The `open` action: open a file, folder or URL in its default app. | launch, browse |
| Run Command | The `exec` action: start a program with arguments. | execute, exec, shell, script |
| Send Shortcut | The `send` action: press one or more key combinations in the app you were using. | send keys, keystroke, type, simulate |
| Context Aware | The `contextual` action: run a different action depending on the app in front. | contextual, conditional, smart action, Choose by App |
| Do Nothing | The `noop` action. | noop, placeholder, empty |
| Show Help | The `help` action: open the Help window. | help, home, open help |
| Context | A named set of apps, such as "browser", that Context Aware actions check against. | app group, profile, scope |
| App in front | The app that was active when you pressed the leader. Actions go to it. | focused app, frontmost, target app |
| Guide | The small panel that shows where you are in a sequence and which keys come next (HUD in the code). | HUD, overlay, popup, palette, cheat sheet |
| Path | The breadcrumb row at the top of the guide: "Commands › Applications". | breadcrumbs, trail, location |
| Back | Go up one menu (Backspace by default). | up, previous, return |
| Cancel | End the sequence without running anything (Escape by default). In a held menu, also its first row, which has no key. | close, abort, exit, dismiss |
| Held menu | A menu that works while you hold its leader's modifiers, and chooses the highlighted item when you let go, as ⌘Tab does (spec v18). Turned on with Hold on a leader. | switcher mode, sticky menu, hold mode |
| Hold to Choose | The switch on a leader that makes its menus held menus (`"hold": true`). | Hold, Hold Mode, Sticky |
| Contents | What a menu holds: Keys You Add, or Recent Windows, which the app fills (`list`). | Fills Itself, Source, Type |
| Highlight | The row of a held menu that letting go chooses. The repeat key, Shift, Down and Up move it. | selection, cursor, focus |
| Repeat key | The key that opened a held menu. Pressed again, it moves the highlight to the next row, as Tab does in ⌘Tab. | cycle key, Tab key, next key |
| List | A menu the app fills when it opens, such as Recent Windows (spec v18). | generated menu, dynamic menu, auto menu |
| More | Key 0 in a list with more than 9 items: go to the next page of 9. | Next, page down, show more |
| Recent Windows | The list of the windows used last, most recent first. | window switcher, MRU, history |
| When Chosen | What choosing an item in Recent Windows does: Focus goes to its window, Swap trades places with it (`choose`, spec v19). | action, select, mode |
| Config file | `~/.config/unnamed-manager/config.json`, the one source of truth for bindings and settings. | settings file, preferences, profile, keymap |
| Starter config | The config file the app writes on first launch when there is none: one leader, two bindings and Show Help. | default config, template, sample |
| Unnamed Launcher | The app Unnamed Manager grew out of. Named only when copying its config or when it's running alongside. | the launcher, the old app, v1 |
| Copy Config | Copy Unnamed Launcher's config file in place of the starter config, on first launch. Its file is never changed. | import, migrate, move, bring over |
| Reload Config | Read the config file again and use it if it's valid. | refresh, restart, re-read |
| Enabled | Whether Unnamed Manager is capturing leaders. When it's off, no keys are captured. | active, running, paused, armed |
| Permissions | The Accessibility and Input Monitoring access in System Settings that the app needs to capture keys. Use Apple's names for each one. | rights, access, privileges |
| Settings | The Settings window (Settings… ⌘,), one tab each: General (Guide, keys, feedback, Open at Login), Bindings, Actions, Contexts and Windows. Name a part as "the Bindings tab" or "Settings › Windows". | Preferences, options, Bindings window, editor |
| Help window | The window with your leaders and direct bindings, the keys that work in every sequence, the built-in actions, and links. Opened by Help, Unnamed Manager Help, or a Show Help binding. | Help page, manual, documentation, cheat sheet |
| Window action | An action that works on the focused window of the app in front: Arrange Windows, Fill, Focus Window, Minimize, Move Window, Place Window, Resize Window, Swap Window, Tidy Windows, Undo Layout. | window command, tiling |
| Arrange Windows | Lay out the window in front and the ones used before it, on its display, in a grid of columns or rows. | tile, pair, snap |
| Cell | One part of the grid Arrange Windows makes, for one window. | slot, tile, pane |
| Group | A column or a row of cells in that grid. | stack, split |
| Tidy Windows | Snap the windows on the display into the columns and rows their places suggest, on its steps (spec v24). | snap, clean up, align, auto-arrange |
| Undo Layout | Put back the windows the last Tidy Windows or Arrange Windows moved; press again to redo (spec v24). | revert, restore layout |
| Step | One of the equal parts a display's usable area is cut into, across and down. Cells and tidied edges land on steps (spec v24). | grid unit, snap point |
| Smallest Cell | The smallest cell Arrange Windows makes, in steps across and down. It sets the most columns and rows (spec v24). | maximum columns, minimum size |
| Floating window | A window Tidy Windows leaves exactly where it is: one in front across a cut, or one its area would make much smaller or bigger (spec v24). | ignored window, excluded |
| Fill | Fill the screen without the menu bar and Dock, less the gap. With Press Again to Restore, pressing it again puts the window back. Called Maximize before spec v7. | maximize, zoom, full screen |
| Focus Window | Bring the nearest window you can see in a direction to the front, the Next Window or Previous Window, or the Window Used Before. | switch, activate, cycle |
| Built-in action | An action every config has without defining it, such as `window-place-left-half` or `window-focus-left`. A binding names it as it names any action. | preset action, default action, standard command |
| Override | An action you define with a built-in action's name. It runs instead of the built-in one everywhere that name is used. | shadow, replace, remap |
| Swap Window | Trade place and size with the window in a direction, the next or previous one, the first or last one, or a Window Number. The window in front keeps focus. | exchange, switch, flip |
| Window Used Before | The window that had focus before the one in front, from the history the app keeps while it runs; it can be behind others, and for Focus Window on another Space ("recent" in the config file). Pressing again goes back. | previous window, last window, recent, toggle |
| Apps (Settings) | The table on Settings' Windows tab of apps with their own window rules: Focus, Swap and Arrange, each checked when that action takes part with the app's windows, and Quit, checked when Quit on Close quits the app ("windows.apps" in the config file). Unchecked is "left out". | excluded, ignored, blacklist, floating |
| Quit on Close | The setting on Settings' Windows tab that quits an app when its last window closes ("windows.quitOnClose"). Finder never quits. | auto quit, close to quit, quit when closed |
| Switch Space | The action that goes to the Space to the left or right, or to one by number, without the slide ("space.switch" in the config file, spec v17; numbers from spec v22). It switches the focused window's display. With no focused window, left and right do nothing, and a number works on the display with the pointer. Numbers count desktops only, as Send to Space does. | Move Space, next desktop, change workspace |
| Send to Space | The action that puts the focused window on the Space to the left or right, or on one by number, counting desktops on its display, and you stay ("space.send" in the config file, spec v20). | Move to Space, push, throw, carry |
| Follow to Space | The action that puts the focused window on another Space as Send to Space does, and you go there with it, without the slide ("space.follow" in the config file, spec v23). | Take to Space, pursue, trail, carry |
| On the Same Display | Keeps Focus Window and Swap Window to the display of the window in front ("scope" in the config file). On Every Display is the default. | this screen, current monitor |
| Minimize | Send the window in front to the Dock, as ⌘M does. | hide, dock |
| Move Window | Move the window To a Spot (such as Center) or By Points. Its size stays the same. | position, drag, nudge |
| Place Window | Move and resize the window to a Preset, such as Left Half, or a Custom part of the screen. | snap, tile, layout |
| Resize Window | Change the window's size: Grow Through Widths, Shrink Through Widths, To a Size, or By Points. | scale, size |
| Preset | A named part of the screen for Place Window, such as Left Half or Top Right Quarter. | layout, zone, snap area |
| Spot | A named place for Move Window, such as Center or Top Left. | position, location |
| Keep in Place | The point of a window that stays put while Resize Window changes its size, such as its Top Left Corner. "Anchor" in the config file. | anchor, origin, pin |
| Gap Between Windows | The space, in points, Place Window leaves between a window and the screen's edges and between windows side by side (`windows.gap`, default 8). Set in Settings › Windows. | padding, margin, spacing, gutter |
| Widths | The list of widths, in % of the screen, that Grow and Shrink go through. | sizes, steps, presets |
| Screen (for window actions) | The display the window is mostly on, without the menu bar and Dock ("usable area" in the spec). | visible frame, work area, desktop |
