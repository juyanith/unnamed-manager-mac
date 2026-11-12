# Architecture review, end of M9 (2026-11-11)

M9 renamed the app, added `LauncherMigration` (one app file, S-058) and `ConfigRule` (one Kit file, S-059). Neither touched more than a few files, and no file is over 330 lines. The next milestone is the one that strains the code: M10 and M11 add six action types.

## Action families behind one registry  [Strong]

Files: `Kit/Config.swift` (269 lines), `Kit/ConfigWriter.swift`, `Kit/ConfigSchema.swift`, `Kit/ActionPlan.swift`, `Kit/Icons.swift`, `App/ActionRunner.swift`, `App/ActionsPage.swift` (298 lines)
Signal: one feature touches more than 6 files and 2 targets. Show Help (S-053) changed all eight places above, plus the Type list in two of them. M11 adds six types, which today means about 50 edits to shared switches.
Problem: an action type is spread over the enum's case, its `type` string, its UI name, its decoder, its writer, its schema variant, its plan, its performer, its icon, its form and the Type picker's list. Nothing checks that a new type got all of them; a missed writer case only shows up when the Bindings window saves.
Proposal, designed twice:

- (a) **One enum case per family** (`case window(WindowAction)`), with the family's own enum in its own file. Switches stay exhaustive, so the compiler finds every place. But each new family still adds a case to about eight shared switches.
- (b) **A registry of families.** A family is one type that owns its `type` strings, decoding, writing, schema, UI name, symbol and plan, in the Kit; the app adds its performer and its form. Adding one is new files plus one line in the registry.

Pick (b). The brief asks for families that "touch no shell code", and the cost of type erasure stays in two small places (`AnyActionValue`, and the app's lookup of performer and form by family). A unit test over the registry replaces the compiler's exhaustiveness: unique types, a UI name and symbol for each, a schema variant that round-trips, a writer that round-trips.

```swift
// Kit
public protocol ActionFamily: Sendable {
    associatedtype Value: Sendable & Equatable
    static var kinds: [ActionKind] { get }          // type string, UI name, SF Symbol
    static func decode(_ type: String, _ fields: ConfigObject) throws -> Value   // throws ConfigIssue with a ConfigRule
    static func encode(_ value: Value) -> [(key: String, value: JSONValue)]      // stable key order
    static func schema(for type: String) -> [String: Any]
    static func plan(_ value: Value, in context: PlanContext) throws(PlanError) -> ActionPlan
}
public enum ActionRegistry { public static let families: [any ActionFamily.Type] }
// Config.Action: .contextual(variants:fallback:) stays; every other type becomes .family(AnyActionValue).

// App
protocol ActionPerformerFamily { associatedtype Family: ActionFamily; func perform(_ step: ActionPlan) async throws }
protocol ActionFormFamily { associatedtype Family: ActionFamily; @MainActor func form(_ value: Binding<Family.Value>) -> AnyView }
```

**Context Aware stays a shell case.** It combines other actions and refers to contexts, so the validator, `ContextResolver` and the Contexts page need to see inside it. That changes one line of S-060: six of the seven existing types become families, not seven.

Benefits:
- **Locality:** a window action lives in `Kit/Actions/Window*.swift` and `App/Actions/Window*.swift`, and nowhere else.
- **Leverage:** the schema, the writer's key order, the Type picker, the Guide's default symbol and the spec fixtures pick up a new type for free.
- Tests get simpler: one registry test replaces the per-type "is in the picker" and "is in the schema" checks.

Proof of same behavior:
- Golden files recorded before step 1: the generated schema's bytes, and `ConfigWriter`'s output for every valid spec fixture and the seed config.
- All 142 unit tests (with `SpecFixtureTests` and its 45 fixtures) and the 135 self-test checks pass unchanged.
- The `actions-*`, `actions-help`, `hud` and `bindings` snapshots match.

Plan, one commit per step, each building:
1. Record the golden schema and writer outputs as tests.
2. Add `ActionFamily`, `ActionKind`, `AnyActionValue`, `ActionRegistry` and the registry test, in new Kit files, with no families yet.
3. Move Do Nothing and Show Help (no fields) into families, and add the `.family` case.
4. Move Open, Run Command and Send Shortcut.
5. Move Use Application, with its mode and its icon.
6. App: performers and forms looked up by family; the Type picker reads the registry.
7. A family registered only in the tests loads, writes, appears in the schema and runs through `RecordingPerformer`, with no edit to shared files (S-060's last line).

## Keyboard capture and sequence session  [Worth exploring]

Carried over from M6 and M8. `Launcher` (205 lines) owns permissions, Secure Input, the tap, Enabled, the engine, the schedule and the Guide. Two reasons to do it now: the name reads wrong in Unnamed Manager, and M11's window actions need "the focused window of the app in front", taken when the sequence starts, which belongs to the session half. Split it into `KeyboardAccess` and `SequenceSession` just before S-062.

## Window system seam  [Worth exploring]

Not a refactor, a shape for M11's new code. Put the geometry (fractions to frames, the Accessibility and `NSScreen` coordinate flip, clamping, directional neighbors, next and previous order) in a pure Kit module, `WindowGeometry`, and the Accessibility calls behind a `WindowSystem` protocol with two adapters: `AXWindowSystem` and a `FakeWindowSystem` for the self-test. Every M11 story already has `[unit]` lines for the first and "against a fake window" lines for the second.

## Snapshot pages from a table  [Speculative]

Carried over. `Snapshot.swift` is 252 lines; S-058 added one more block in the same "light and dark, set up, wait, capture" shape, and found that a single `Window` reuses its NSWindow (look windows up by id). M11 adds two pages. Do it when the file passes 300 lines.

## Considered, not recommended

- **Moving Context Aware into a family.** It's a combinator over other actions; a family that reaches into the registry and the contexts is a worse home than the shell.
- **Making `ConfigIssue.rule` required.** Issues about reading or saving the file, and the editor's draft check, have no spec rule. `SpecFixtureTests` already fails when a file-contents issue lacks one.
- **Moving `LauncherMigration` into the Kit.** Its rules are three booleans, checked by the self-test, and the file is meant to be deleted in one piece once nobody runs Unnamed Launcher.

## Top recommendation

**Action families behind one registry**, as M10 (S-060), in the seven steps above. Change S-060's acceptance to "six of the seven existing types are families; Context Aware stays in the shell". Then the window system seam as M11 starts.
