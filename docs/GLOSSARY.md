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
| Show Help | The `help` action: open the Help page of the Bindings window. | help, home, open help |
| Context | A named set of apps, such as "browser", that Context Aware actions check against. | app group, profile, scope |
| App in front | The app that was active when you pressed the leader. Actions go to it. | focused app, frontmost, target app |
| Guide | The small panel that shows where you are in a sequence and which keys come next (HUD in the code). | HUD, overlay, popup, palette, cheat sheet |
| Path | The breadcrumb row at the top of the guide: "Commands › Applications". | breadcrumbs, trail, location |
| Back | Go up one menu (Backspace by default). | up, previous, return |
| Cancel | End the sequence without running anything (Escape by default). | close, abort, exit, dismiss |
| Config file | `~/.config/unnamed-manager/config.json`, the one source of truth for bindings and settings. | settings file, preferences, profile, keymap |
| Reload Config | Read the config file again and use it if it's valid. | refresh, restart, re-read |
| Enabled | Whether Unnamed Manager is capturing leaders. When it's off, no keys are captured. | active, running, paused, armed |
| Permissions | The Accessibility and Input Monitoring access in System Settings that the app needs to capture keys. Use Apple's names for each one. | rights, access, privileges |
| Bindings window | The window for editing bindings, actions and contexts, opened by Edit Bindings… (⌘B). | editor, config editor, settings window |
| Help page | The Help page of the Bindings window: your leaders and direct bindings, the keys that work in every sequence, and links. | manual, documentation, cheat sheet |
| Settings | The Settings window (Settings… ⌘,): Guide, keys, feedback, Open at Login. | Preferences, options |
