import CoreGraphics
import UnnamedManagerKit

extension WindowControl {
    /// Arrange Windows (S-075, S-076): the windows on the focused window's
    /// display, the focused one first and then front to back, each in the
    /// cell `ArrangeGrid` gives it. With no focused window, the one in front
    /// counts as focused.
    /// Apps with `"arrange": false` in `windows.apps` are never counted or
    /// moved (S-084, spec v15); when the focused window is one of theirs, its display is
    /// still the one arranged, and the window in front there counts as focused.
    func arrange(_ action: ArrangeAction, focused: WindowRef?) throws(PlanError) {
        let excluded = settings().leftOut(of: \.arrange)
        let screens = system.screens(), candidates = system.focusableWindows().filter { !$0.isLeftOut(of: \.arrange, apps: excluded) }
        guard let anchor = focused.flatMap({ system.frame(of: $0) }) ?? candidates.first?.frame,
              let screen = WindowGeometry.screen(for: anchor, among: screens) else {
            throw PlanError("No window to arrange.")
        }
        var windows = candidates.filter { WindowGeometry.screen(for: $0.frame, among: screens) == screen }
        if let index = windows.firstIndex(where: { $0.ref == focused }) {
            windows.insert(windows.remove(at: index), at: 0)
        }
        guard !windows.isEmpty else { throw PlanError("No window to arrange.") }
        let settings = settings()
        let plan = ArrangeGrid.plan(action, maxColumns: settings.maxColumns, maxRows: settings.maxRows,
                                    usable: screen.usable, windows: windows.map(\.frame))
        for (index, cell) in plan {
            let frame = cell.rect(in: screen.usable)
            // A window that's in its cell already stays untouched, so the action can be repeated.
            if !WindowGeometry.matches(windows[index].frame, WindowGeometry.withGap(frame, in: screen.usable, gap: gap)) {
                place(windows[index].ref, in: frame, on: screen)
            }
        }
    }
}
