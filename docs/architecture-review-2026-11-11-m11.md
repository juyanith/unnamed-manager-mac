# Architecture review, end of M11 (2026-11-11)

M11 added six window actions on the M10 registry and the window system seam the M10 review proposed. Survey: 9,924 lines of Swift; no file over 330 (`ConfigDocument.swift` 321). The hot spots of the milestone are the new window files themselves. No duplicated private types. Two small refactors were done in this check-in (below); the rest is for the user to pick.

## Done in this check-in

- **`WindowRaiser` folded into `AXWindowSystem`** [Strong]. It kept its own copy of the Accessibility read helper and timeout. Proof: 160 self-test checks, S-047's included, before and after.
- **`WindowForms.swift` split** (312 lines) into the forms and `WindowFormParts.swift` (names, number fields). Proof: the actions-window snapshots are unchanged.

## Window commands as values the Kit decides  [Worth exploring]

Files: `Sources/UnnamedManager/Windows/WindowSystem.swift` (`WindowControl`, 120 lines), `Sources/UnnamedManagerKit/Actions/Window/WindowCommand.swift`
Signal: one feature touched several shared files. Each window action added a case to `WindowCommand` and a branch to `WindowControl.run`, so the window families don't yet keep M10's promise of one file per family.
Problem: `WindowControl.run` mixes decisions (which frame, which window) with effects (set the frame, read it back, re-anchor). The decisions are tested through `WindowGeometry`, but the re-anchoring after a window refuses a size lives only in the app and is checked only against the fake.
Proposal:

```swift
// Kit: each window family plans a value that decides, given what it sees.
public protocol WindowStep: ActionStep {
    func decide(_ seen: WindowScene, memory: inout WindowMemory) throws(PlanError) -> [WindowEffect]
}
public enum WindowEffect: Equatable { case setFrame(CGRect), minimize, focus(Int), reanchor(WindowAnchor, in: CGRect) }
// App: WindowControl reads a WindowScene, runs the effects, nothing else.
```

Benefits: a new window action is one Kit file; `WindowControl` stops growing; every decision, re-anchoring included, is unit-tested.
Proof of same behavior: the 199 unit tests, the 160 self-test checks, the window fixtures.
Plan: (1) `WindowScene` and `WindowEffect` in the Kit; (2) move Maximize and Minimize; (3) Place, Move, Resize; (4) Focus; (5) delete `WindowCommand`.
Do it before the next window action (moving windows between displays or Spaces, in Later).

## Keyboard capture and sequence session  [Speculative]

Carried over. `Launcher` is still 205 lines, and M11 didn't need the split: the front app is read when the action runs, which is what the Guide leaves in front. Do it when a story needs the focused window captured at the first key.

## Snapshot pages from a table  [Worth exploring]

Carried over. `Snapshot.swift` is 273 lines, up 21 with two window blocks in the same "light and dark, set up, wait, capture" shape. Do it when it passes 300.

## Considered, not recommended

- **The private window id for matching windows** (`_AXUIElementGetWindow`). Matching the window server's list to Accessibility windows by owner and frame works without private API; two windows of one app with the same frame are the only miss.
- **Moving the forms' UI names into the Kit.** They're words for the Mac's UI; the Windows app has its own. The Kit keeps the spec's names only.
- **One window family for all six types.** The spec gives each its own fields, and separate families keep each decoder small.

## Top recommendation

**Window commands as values the Kit decides**, before the next window action. Nothing in M11 needs it now, and the user decides when M12 starts.
