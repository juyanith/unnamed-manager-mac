# Architecture review, end of M12 (2026-11-21)

M12 added held menus and Recent Windows (S-089 to S-095). Since the M11 review the app also gained Window Used Before, per-app rules, Quit on Close, the Spaces settings, Switch Space and Send to Space (S-083 to S-088, S-096). Survey: 79 commits; 19,691 lines of Swift, tests included. The unit tests (330), the self-test (290 checks) and the grid checks all pass. Nothing was refactored in this check-in.

Since the M11 review, these files grew the most:

| File | M11 | Now | What came in |
| --- | --- | --- | --- |
| `Windows/WindowSystem.swift` (`WindowControl`) | 118 | 516 | Window Used Before, seen windows, Recent Windows, choosing and swapping from a list, Switch Space, Send to Space |
| `SelfTest+Windows.swift` | 181 | 819 | Ten check groups, one per story area |
| `SequenceEngine.swift` (Kit) | 197 | 409 | The highlight, hold, filling lists and paging them |
| `Launcher.swift` | 205 | 325 | Watching a hold, and filling, watching and choosing from a list |
| `Snapshot.swift` | 273 | 351 | New pages for held menus, lists and window forms |

The M11 review's top recommendation (Kit-decided window commands, "before the next window action") wasn't done. Seven window features came after it, and `WindowControl` has more than quadrupled in size.

## `WindowControl` in files by area  [Strong]

Files: `Sources/UnnamedManager/Windows/WindowSystem.swift`
Signal: it's the second most-changed source file since M11 (19 commits), and one feature touched it in every story from S-083 to S-096. It holds the seam protocol, four value types, and `WindowControl` with focus, swap, arrange, the focus history, Recent Windows and Send to Space.
Problem: every window story edits this one file, and a reader has to scroll past five areas to find one. The seam (`WindowSystem` and its value types) is hard to see among the logic that uses it.
Proposal: move code only; no behavior changes.

```text
Windows/WindowSystem.swift       the protocol, WindowRef, WindowInfo, ListedWindow, FrontApp
Windows/WindowControl.swift      the class, its state, run(_:), go(to:), recent(…)
Windows/WindowControl+Focus.swift   focus and swap, with place(of:in:)
Windows/WindowControl+Arrange.swift arrange
Windows/WindowControl+Recent.swift  RecentWindow, recentWindows, choose, swap(with:), exists
Windows/SpaceSend.swift          gains WindowControl.send(to:follow:) and swipe(from:to:around:)
```

Benefits: each window story touches the file for its area. The seam file shrinks to about 100 lines and matches the table in ARCHITECTURE.md.
Proof of same behavior: the 290 self-test checks (all the window ones run through `WindowControl` against `FakeWindowSystem`) and the 330 unit tests, before and after.
Plan: one commit, moving code only. A `private` member that another area's file uses becomes `internal`, or stays in `WindowControl.swift`.

## A list session out of `Launcher`  [Strong]

Files: `Sources/UnnamedManager/Launcher.swift` (`fill`, `watchList`, `choose`, and the `listed`, `listSwaps`, `nextItemID` and `listWatch` state)
Signal: carried over since M6 as "split `Launcher`", always waiting for a feature that needed it. M12 was that feature: lists put a second session's state into the class that owns permissions, the tap and Enabled.
Problem: Recent Windows' item ids, the id-to-window map, the closed-window watch and swap-or-focus live beside permissions and Secure Input. The self-test reaches them only through `Launcher`, and `Launcher` gets the 100 ms hold watch and the 250 ms list watch as two more `Task` properties.
Proposal:

```swift
/// One list while it's up (S-092 to S-095): its items' windows, the
/// watch that takes out closed ones, and what choosing does.
@MainActor final class ListSession {
    init(windows: WindowControl, engine: EngineBox)
    func fill(_ menu: BindingNode) -> [SequenceEffect]   // the effects Launcher applies
    func choose(_ item: ListItem) async throws(PlanError)
    func end()                                            // cancels the watch
}
```

`Launcher.apply` calls `fill` and `choose`; the hold watch stays in `Launcher` with the engine. This is the first half of the old `KeyboardAccess` / `SequenceSession` split, and only the half a story now needs.
Benefits: `Launcher` is back near 250 lines. The list's lifetime is one object's, so "only the list just opened can be chosen from" is a new instance, not a cleared dictionary.
Proof of same behavior: the 380-line `SelfTest+Held.swift` (S-090 to S-095) and `HeldMenuTests` and `ListTests`.
Plan: (1) move the state and the three functions; (2) end the session on `.endSequence`; (3) point the self-test at `ListSession` where it reads `Launcher`'s list state.

## Window commands as values the Kit decides  [Worth exploring]

Carried over from M11, with a stronger signal. `WindowCommand` has eight cases, and `WindowControl.run` still mixes decisions with effects. Focus, swap, Recent Windows' order and Send to Space's target are already Kit decisions (`WindowGeometry.neighbor` and the focus order, `RecentWindows`, `SpaceSend.pick`), so what's left in the app is mostly reading the scene and carrying out effects. Do the file split above first: it shows how much is left. Do this before "pick a window from an overlay" (in Later), which adds a target to both Focus Window and Swap Window.

## The window self-test in files by area  [Worth exploring]

`SelfTest+Windows.swift` is 819 lines, the largest file in the repo. It's already ten `static func …Checks()` groups, so it splits along them with no other change: Focus and Swap, Arrange, Recent Windows and seen windows, Spaces (settings, switch, send), editing. Proof: the same 290 checks, in the same order. It's only test code, so do it alongside the `WindowControl` split.

## Snapshot pages from a table  [Worth exploring]

Carried over. The M11 review said to do it when `Snapshot.swift` passed 300 lines, and it's at 351. M12 added three more blocks in the same "light and dark, set up, wait, capture" shape.

## Held and list state in the engine as values  [Speculative]

`SequenceEngine` doubled, but it's pure Kit code with its own tests, and each rule is short. Four of its properties belong together and are nil or empty outside a hold or a pending list: `highlight` and `holdModifiers`, and `pending` and `pendingHeld`. As `held: Held?` and `pendingList: PendingList?`, "no highlight unless held" would be something the type enforces. Do it if the engine passes 450 lines, or with double-tap modifier leaders, which add another kind of hold.

## Considered, not recommended

- **A protocol around SkyLight.** `SpaceSend.swift` keeps every private SkyLight call, the symbol-table lookup and the title-bar fallback in one app file, behind `WindowSystem.desktop` and `.send`. The fake already stands in for all of it, and the risk (macOS 27.3 refusing the bridged move) is written down in S-096.
- **Moving Recent Windows' filling off the main thread.** Reading every app's windows is the slow part, but Accessibility calls have to run on the main thread or a thread of their own per app. The engine already waits and replays keys. Measure with many apps open first (S-092's open manual line).
- **Making Reduce Motion a switch.** macOS lets apps read it but not set it: the setter is private, and its storage needs an Apple-only entitlement. The Windows tab reads it and links to Accessibility settings (S-087).

## Top recommendation

**Split `WindowControl` into files by area, and move lists into a `ListSession`**, both before M13. Each is one commit of moving code, and the existing checks cover both. Both M13 candidates in Later land on them: picking a window from an overlay changes focus and swap, and double-tap modifier leaders change `Launcher`.
