# Architecture review, end of M10 (2026-11-11)

M10 was itself the refactor from the M9 review: every type except Context Aware is now an action family behind `ActionRegistry`, proven by golden files and by two families that exist only in tests. This check-in asks what M11's window actions need.

Survey: no Swift file over 330 lines (`ConfigDocument.swift` 321, `SelfTest+Launcher.swift` 296, `Guide.swift` 274). `ActionsPage.swift` dropped to 223 and `Config.swift` to 251 as the type-specific code moved into `Actions/`. No duplicated private types. No new fix-log entries since M9.

## Window system seam, with a context for a family's step  [Strong, as the first commit of S-062]

Files: `Sources/UnnamedManager/ActionRunner.swift` (`PerformableStep`), `Sources/UnnamedManager/WindowRaiser.swift` (47 lines, the only Accessibility code)
Signal: before a big feature; a dependency that can't be replaced in a test.
Problem: `PerformableStep.perform()` takes nothing. A window step can only reach Accessibility through globals, so the M11 lines "against a fake window" (S-062 to S-068) can't be checked, and the step can't know which window was in front when the sequence started.
Proposal:

```swift
// Kit: pure geometry, unit-tested.
public enum WindowGeometry {
    static func frame(_ place: Placement, in visible: CGRect) -> CGRect
    static func neighbor(of window: CGRect, _ direction: Direction, among: [CGRect]) -> Int?
}
// App: the seam, two adapters (AXWindowSystem, FakeWindowSystem).
protocol WindowSystem {
    func focusedWindow(pid: pid_t) -> WindowRef?
    func frame(of: WindowRef) -> CGRect?
    func setFrame(_: CGRect, of: WindowRef) throws(PlanError)
}
struct StepContext { let windows: any WindowSystem; let frontApp: FrontApp? }
protocol PerformableStep: ActionStep { func perform(in: StepContext) async throws(PlanError) }
```

Benefits: each window action is a Kit family plus one app conformance, as M10 promised; the self-test runs them against `FakeWindowSystem`; `WindowRaiser` becomes the first user of `AXWindowSystem`.
Proof of same behavior: the 141 self-test checks and 155 unit tests; `ChimeStep` moves to the new signature.
Plan: (1) `StepContext` and the new `perform(in:)`, passed by `ActionRunner`; (2) `WindowSystem` with `AXWindowSystem` taking over `WindowRaiser`, and `FakeWindowSystem`; (3) `WindowGeometry` with S-062's first unit lines.

It isn't done in this check-in: with no window action yet, `StepContext` would carry nothing that's used, a hypothetical seam. It belongs at the start of S-062, where its first real user arrives.

## Keyboard capture and sequence session  [Worth exploring]

Carried over from M9. `Launcher` (205 lines) is unchanged. The front app already travels with `SequenceEffect.run`, so `StepContext.frontApp` needs no split. Do the split when S-062 also needs the focused window captured at the first key, or when `Launcher` passes 300 lines.

## Snapshot pages from a table  [Speculative]

Carried over. `Snapshot.swift` is still 252 lines. Do it when it passes 300.

## Considered, not recommended

- **Moving family forms into the Kit.** The Kit has no SwiftUI on purpose; `EditableAction` keeps each form in one app file next to nothing else.
- **A mutable global registry that families add themselves to.** The order would depend on load order, and tests would leak families into each other. `adding` builds a new value instead.
- **Making every `ActionPlan` case a custom step.** The six built-in cases are checked by exact equality in many tests and need no per-family code; only new families use `.custom`.

## Top recommendation

No refactor at this check-in; the code is in good shape. Start S-062 with the window system seam in the three steps above.
