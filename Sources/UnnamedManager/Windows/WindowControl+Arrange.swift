import CoreGraphics
import UnnamedManagerKit

extension WindowControl {
    /// The windows Arrange Windows and Tidy Windows work on: those on the
    /// focused window's display, the focused one first and then front to
    /// back. With no focused window, the one in front counts as focused.
    /// Apps with `"arrange": false` in `windows.apps` and dialogs are never
    /// counted or moved (S-084, spec v15 and v21); when the focused window
    /// is one of theirs, its display is still the one used, and the window
    /// in front there counts as focused.
    func layoutCandidates(focused: WindowRef?, verb: String) throws(PlanError) -> (screen: WindowGeometry.Screen, windows: [WindowInfo]) {
        let excluded = settings().leftOut(of: \.arrange)
        let screens = system.screens(), candidates = system.focusableWindows().filter { !$0.isLeftOut(of: \.arrange, apps: excluded) }
        guard let anchor = focused.flatMap({ system.frame(of: $0) }) ?? candidates.first?.frame,
              let screen = WindowGeometry.screen(for: anchor, among: screens) else {
            throw PlanError("No window to \(verb).")
        }
        var windows = candidates.filter { WindowGeometry.screen(for: $0.frame, among: screens) == screen }
        if let index = windows.firstIndex(where: { $0.ref == focused }) {
            windows.insert(windows.remove(at: index), at: 0)
        }
        guard !windows.isEmpty else { throw PlanError("No window to \(verb).") }
        return (screen, windows)
    }

    /// Arrange Windows (S-075, S-076): each window in the cell `ArrangeGrid`
    /// gives it, on the display's steps (spec v24).
    func arrange(_ action: ArrangeAction, focused: WindowRef?) throws(PlanError) {
        let (screen, windows) = try layoutCandidates(focused: focused, verb: "arrange")
        let settings = settings()
        let plan = ArrangeGrid.plan(action, steps: settings.steps(for: screen.frame.size), minCell: settings.minCell(for: screen.frame.size),
                                    usable: screen.usable, windows: windows.map(\.frame),
                                    minimums: windows.map { settings.minimum(for: $0.app) })
        apply(plan.map { (windows[$0.window], $0.cell.rect(in: screen.usable)) }, on: screen)
    }

    /// Tidy Windows (spec v24): every candidate on the display, snapped
    /// into the columns and rows `TidyLayout` finds. Floating windows stay.
    func tidy(focused: WindowRef?) throws(PlanError) {
        let (screen, focusedFirst) = try layoutCandidates(focused: focused, verb: "tidy")
        // Front to back, as the platform lists them: the order decides which windows float.
        let windows = system.focusableWindows().filter { window in focusedFirst.contains { $0.ref == window.ref } }
        let settings = settings()
        let plan = TidyLayout.plan(usable: screen.usable, steps: settings.steps(for: screen.frame.size), windows: windows.map(\.frame),
                                   minimums: windows.map { settings.minimum(for: $0.app) },
                                   minCell: settings.minCell(for: screen.frame.size))
        let floating = Set(plan.floating)
        apply(windows.indices.filter { !floating.contains($0) }.map { (windows[$0], plan.frames[$0]) }, on: screen)
    }

    /// Puts each window in its frame, with the gap, and keeps what moved
    /// for Undo Layout. A window already there stays untouched, so the
    /// action can be repeated.
    private func apply(_ moves: [(window: WindowInfo, frame: CGRect)], on screen: WindowGeometry.Screen) {
        var moved: [LayoutUndo.Item] = []
        for (window, frame) in moves where !WindowGeometry.matches(window.frame, WindowGeometry.withGap(frame, in: screen.usable, gap: gap)) {
            place(window.ref, in: frame, on: screen)
            moved.append(.init(window: window.ref, expected: system.frame(of: window.ref) ?? frame, other: window.frame))
        }
        // A layout that moved nothing keeps the undo there was.
        if !moved.isEmpty { undo[LayoutUndo.key(screen)] = LayoutUndo(items: moved) }
    }

    /// Undo Layout (spec v24): puts back the frames the windows had before
    /// the last layout on the focused window's display, and the layout's
    /// frames when pressed again. A window moved since is left alone.
    func undoLayout(focused: WindowRef?) throws(PlanError) {
        let screens = system.screens()
        let anchor = focused.flatMap { system.frame(of: $0) } ?? system.focusableWindows().first?.frame
        guard let screen = anchor.flatMap({ WindowGeometry.screen(for: $0, among: screens) }) ?? screens.first,
              var record = undo[LayoutUndo.key(screen)] else {
            throw PlanError("Nothing to undo.", alerts: true)
        }
        var items: [LayoutUndo.Item] = []
        for item in record.items {
            // Closed, or moved or resized since: it stays where it is, and drops out.
            guard let now = system.frame(of: item.window), WindowGeometry.matches(now, item.expected) else { continue }
            system.setFrame(item.other, of: item.window)
            items.append(.init(window: item.window, expected: system.frame(of: item.window) ?? item.other, other: item.expected))
        }
        record.items = items
        undo[LayoutUndo.key(screen)] = items.isEmpty ? nil : record
        if items.isEmpty { throw PlanError("Nothing to undo.", alerts: true) }
    }
}

/// What Undo Layout puts back on one display (spec v24): for each window
/// the last layout moved, the frame it should have now and the one it goes
/// to. Each press swaps the two. Kept in memory only.
struct LayoutUndo {
    struct Item {
        let window: WindowRef
        let expected: CGRect
        let other: CGRect
    }

    var items: [Item]

    /// One undo for each display, by its frame.
    static func key(_ screen: WindowGeometry.Screen) -> String { "\(screen.frame)" }
}
