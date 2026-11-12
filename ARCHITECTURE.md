# Architecture

## Targets

| Target | Holds | Depends on |
| --- | --- | --- |
| `UnnamedManagerKit` | Pure logic: key names and chords (`Keys.swift`), the config model with strict decoding (`Config.swift`), validation and the binding tree (`ConfigValidator.swift`), the shared spec's rule ids (`ConfigRule.swift`), loading and the starter config (`ConfigLoader.swift`), the sequence engine (`SequenceEngine.swift`), action plans and Context Aware (`ActionPlan.swift`, `ContextResolver.swift`), which icon an entry gets (`Icons.swift`), Home (`Home.swift`), the Guide's timing and placement (`GuideSchedule.swift`, `GuidePlacement.swift`), and editing and writing the file (`ConfigDocument.swift`, `ConfigWriter.swift`, `JSONKeyOrder.swift`). There's no AppKit and no default actor isolation, and everything is `Sendable`. | Foundation |
| `UnnamedManager` | The app: menu bar menu, Bindings window, Settings, the Guide panel, the event tap, actions, permissions. Main-actor by default. | `UnnamedManagerKit`, AppKit, SwiftUI |
| `UnnamedManagerKitTests` | Unit tests for every validation rule and engine rule, and `SpecFixtureTests`, which runs the shared spec's fixtures. | `UnnamedManagerKit`, `spec/` |
| `spec/` | A git submodule of the `unnamed-manager` repo: the config format shared with the Windows app, its schema and fixtures. Never edited from here. | none |

Dependencies point one way: the app depends on the Kit, and the Kit depends on nothing of ours.

## Runtime

```text
tap thread                                   main thread
──────────                                   ───────────
CGEvent tap ─► TapContext ─► EngineBox ──┐
   (KeyCapture, TapLoop)    (Mutex around │
                             SequenceEngine)
                 consume / pass ◄─────────┤
                                          └─ DispatchQueue.main ─► Launcher.apply(effect)
                                                                     ├─ GuideController (show, hide)
                                                                     └─ ActionRunner (Use Application, …)
ConfigStore (main) ── onLoad ─► EngineBox.replace(config)
                             └─► GuideIcons.load(config.iconSources())
```

- **The event tap runs on its own thread** (`net.unnamed.manager.event-tap`, user-interactive). The callback decides consume or pass at once, from the engine alone. A busy main thread never delays a keystroke.
- **Effects reach the main queue in order:** show the Guide, run an action, cancel, or an unbound-key error.
- **`ConfigStore` is the one owner of the file:** it reads, validates, saves atomically, refuses a document with errors, and watches the folder for outside edits. The Bindings window and Settings edit a draft `ConfigDocument` through `BindingsEditor`.
- **`ConfigStore` loads and validates on the main thread.** A valid config replaces the engine's config under the lock. A reload with errors keeps the last valid one.
- **Icons are looked up when the config loads, never when the Guide shows.** `IconSource` (Kit) names where an icon comes from; `GuideIcons` (main) caches the images; `EntryIcon` draws one the same way in the Guide and the Bindings editor, and only the editor looks up on a miss. `AppGlyph` draws the app's glyph for the menu bar and for menus.
- **`Launcher` owns permissions, Enabled, the tap, the engine box and the Guide.** The menu bar menu reads its state through `MenuBarStatus`, a plain value the self-test checks.

## Seams

| Seam | Adapters | Test use |
| --- | --- | --- |
| `ConfigLocation` (`APP_STORE`) | the real `~/.config/unnamed-manager/config.json`; a file in `/tmp` | The self-test and snapshots never touch the real config |
| `Launcher.start(captureKeys:)` | the real tap; no tap | Snapshots and the self-test never capture the keyboard |
| `KeyEvent` into `SequenceEngine` | the event tap; unit tests | Every sequence rule is tested without a keyboard |
| `ActionPerformer` | `SystemPerformer` (NSWorkspace, Process, CGEvent); `RecordingPerformer` | The self-test checks action plans without launching or typing anything |
| `LauncherMigration.sourceURL` (`APP_LAUNCHER_STORE`) | the real Unnamed Launcher config; a file in `/tmp`; none while `APP_STORE` is set | The self-test copies a config without reading the real one. `LauncherMigration.swift` is the one file that names the old app (`AppNameTests`) |

## Reviews

- [docs/architecture-review-2026-11-08.md](docs/architecture-review-2026-11-08.md) (end of M1)
- [docs/architecture-review-2026-11-08-m2.md](docs/architecture-review-2026-11-08-m2.md) (end of M2)
- [docs/architecture-review-2026-11-08-m3.md](docs/architecture-review-2026-11-08-m3.md) (end of M3)
- [docs/architecture-review-2026-11-08-m4.md](docs/architecture-review-2026-11-08-m4.md) (end of M4)
- [docs/architecture-review-2026-11-08-m5.md](docs/architecture-review-2026-11-08-m5.md) (end of M5)
- [docs/architecture-review-2026-11-08-m6.md](docs/architecture-review-2026-11-08-m6.md) (end of M6, version one)
- [docs/architecture-review-2026-11-11-m8.md](docs/architecture-review-2026-11-11-m8.md) (end of M8; one home for Guide icons, done)
- [docs/architecture-review-2026-11-11-m9.md](docs/architecture-review-2026-11-11-m9.md) (end of M9; action families behind one registry, next as M10)
