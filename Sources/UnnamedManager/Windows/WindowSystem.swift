import CoreGraphics
import UnnamedManagerKit

/// One window, as a window system knows it. Equal for the same window
/// across calls, so Fill can remember it.
struct WindowRef: Hashable {
    let id: AnyHashable
}

/// A window Focus Window can go to.
struct WindowInfo {
    let ref: WindowRef
    let frame: CGRect
    let pid: pid_t
}

/// The app in front, which window actions work on.
struct FrontApp: Equatable {
    let pid: pid_t
    let name: String
}

/// The seam between window actions and the windows on screen (S-062).
/// `AXWindowSystem` uses Accessibility; `FakeWindowSystem` keeps frames in
/// memory for the self-test.
protocol WindowSystem: AnyObject {
    /// False when Accessibility isn't allowed, so no window can move.
    var canControlWindows: Bool { get }
    func frontApp() -> FrontApp?
    func focusedWindow(of app: FrontApp) -> WindowRef?
    func frame(of window: WindowRef) -> CGRect?
    /// Best effort: a window that won't take the frame ends as close as it allows.
    func setFrame(_ frame: CGRect, of window: WindowRef)
    /// Sends the window to the Dock. The app focuses its next window, as for ⌘M.
    func minimize(_ window: WindowRef)
    /// Every display, main display first.
    func screens() -> [WindowGeometry.Screen]
    /// The standard, visible windows that aren't minimized, on the current
    /// Space of every display, without this app's own (S-068), front to back.
    func focusableWindows() -> [WindowInfo]
    /// Brings a window and its app to the front with focus.
    func focus(_ window: WindowInfo) async throws(PlanError)
}

/// Carries out window commands on the focused window of the app in front,
/// and keeps what Fill remembers (S-062).
final class WindowControl {
    let system: any WindowSystem
    private var filled = FillMemory<WindowRef>()

    /// The window settings: the gap (spec v3, v7) and Arrange Windows' limits (spec v8), read when an action runs.
    let settings: () -> Config.Windows
    private var gap: CGFloat { CGFloat(settings().gap).rounded() }

    init(system: any WindowSystem, settings: @escaping () -> Config.Windows = { Config.Windows() }) {
        self.system = system
        self.settings = settings
    }

    func run(_ command: WindowCommand) async throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to move windows.")
        }
        let app = system.frontApp()
        let focused = app.flatMap { system.focusedWindow(of: $0) }
        // Focus Window and Arrange Windows also work with no focused window.
        switch command {
        case let .focus(direction, scope):
            try await focus(direction, scope: scope, from: focused)
            return
        case let .arrange(action):
            try arrange(action, focused: focused)
            return
        default:
            break
        }
        guard let app else { throw PlanError("No app is in front.") }
        guard let window = focused, let frame = system.frame(of: window) else {
            throw PlanError("\(app.name) has no window to \(command.verb).")
        }
        guard let screen = WindowGeometry.screen(for: frame, among: system.screens()) else { return }
        switch command {
        case let .fill(toggle):
            switch filled.step(for: window, frame: frame, area: WindowGeometry.withGap(screen.usable, in: screen.usable, gap: gap), toggle: toggle) {
            case let .fill(area):
                system.setFrame(area, of: window)
                filled.record(window, before: frame, after: system.frame(of: window) ?? area)
            case let .restore(before):
                system.setFrame(before, of: window)
            case .stay:
                break
            }
        case .minimize:
            system.minimize(window)
        case let .place(fractions):
            place(window, in: WindowGeometry.rect(fractions, in: screen.usable), on: screen)
        case let .resize(.step(step, widths), _):
            if let next = WindowGeometry.step(frame, in: screen.usable, widths: widths ?? ResizeAction.defaultWidths, step) {
                system.setFrame(next, of: window)
            }
        case let .resize(change, anchor):
            guard let size = WindowGeometry.size(frame, in: screen.usable, change) else { return }
            system.setFrame(WindowGeometry.resized(frame, to: size, keeping: anchor, in: screen.usable), of: window)
            // A window with a fixed, minimum or maximum size keeps its anchor at the size it took.
            if let actual = system.frame(of: window), actual.size != size {
                system.setFrame(WindowGeometry.resized(frame, to: actual.size, keeping: anchor, in: screen.usable), of: window)
            }
        case let .move(move):
            system.setFrame(WindowGeometry.moved(frame, in: screen.usable, move), of: window)
        case let .swap(target, scope):
            try swap(window, at: frame, with: target, scope: scope)
        case .focus, .arrange:
            break
        }
    }

    /// Focus Window's candidates (S-068). With `"scope": "display"`, only
    /// those on the display of `anchor`, or of the window in front without
    /// one (S-078).
    private func candidates(_ scope: WindowScope, around anchor: CGRect?) -> [WindowInfo] {
        let windows = system.focusableWindows()
        guard scope == .display, let anchor = anchor ?? windows.first?.frame else { return windows }
        let screens = system.screens()
        let screen = WindowGeometry.screen(for: anchor, among: screens)
        return windows.filter { WindowGeometry.screen(for: $0.frame, among: screens) == screen }
    }

    /// Focus Window (S-068, S-069, S-072, S-073, S-078). Finding no window
    /// plays the alert sound (spec v10).
    private func focus(_ direction: FocusDirection, scope: WindowScope, from focused: WindowRef?) async throws(PlanError) {
        let frame = focused.flatMap { system.frame(of: $0) }
        let windows = candidates(scope, around: frame)
        let order = WindowGeometry.cycleOrder(windows.map(\.frame), owners: windows.map(\.pid), screens: system.screens())
        // First and Last don't need a focused window, and stay on a window that's already there (S-073).
        if direction == .first || direction == .last {
            guard let index = direction == .first ? order.first : order.last else { throw PlanError(direction.failure, alerts: true) }
            if windows[index].ref != focused { try await system.focus(windows[index]) }
            return
        }
        // With no focused window, any other direction goes to the window in front of the others (S-072, spec v5).
        guard let frame else {
            guard let top = windows.first else { throw PlanError("No window to focus.", alerts: true) }
            try await system.focus(top)
            return
        }
        if direction == .next || direction == .previous {
            guard let index = WindowGeometry.step(from: windows.firstIndex { $0.ref == focused }, in: order, direction) else {
                throw PlanError(direction.failure, alerts: true)
            }
            try await system.focus(windows[index])
            return
        }
        let others = windows.filter { $0.ref != focused }
        guard let index = WindowGeometry.neighbor(of: frame, direction, among: others.map(\.frame)) else {
            throw PlanError(direction.failure, alerts: true)
        }
        try await system.focus(others[index])
    }

    /// Swap Window (S-077): the focused window and the one `target` names
    /// trade frames, and focus stays. Finding no window plays the alert
    /// sound (spec v10).
    private func swap(_ window: WindowRef, at frame: CGRect, with target: SwapTarget, scope: WindowScope) throws(PlanError) {
        let windows = candidates(scope, around: frame)
        switch WindowGeometry.swapPartner(target, current: windows.firstIndex { $0.ref == window }, frame: frame,
                                          windows: windows.map(\.frame), owners: windows.map(\.pid), screens: system.screens()) {
        case let .none(failure):
            throw PlanError(failure, alerts: true)
        case .stay:
            break
        case let .window(index):
            let other = windows[index]
            put(window, in: other.frame)
            put(other.ref, in: frame)
        }
    }

    /// Gives a window another's frame as it is. One that won't take the
    /// size keeps the edge on the usable area's edge, a gap in, as with Place Window.
    private func put(_ window: WindowRef, in target: CGRect) {
        system.setFrame(target, of: window)
        guard let actual = system.frame(of: window), !WindowGeometry.matches(actual, target),
              let screen = WindowGeometry.screen(for: target, among: system.screens()) else { return }
        system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: screen.usable.insetBy(dx: gap, dy: gap)), of: window)
    }

    /// Puts a window in `frame` on a screen, with the gap around it.
    private func place(_ window: WindowRef, in frame: CGRect, on screen: WindowGeometry.Screen) {
        let gap = gap
        let target = WindowGeometry.withGap(frame, in: screen.usable, gap: gap)
        system.setFrame(target, of: window)
        // A window with a minimum or maximum size keeps the edge it was placed against, a gap in from the screen's.
        if let actual = system.frame(of: window), !WindowGeometry.matches(actual, target) {
            let inside = screen.usable.insetBy(dx: gap, dy: gap)
            system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: inside), of: window)
        }
    }

    /// Arrange Windows (S-075, S-076): the windows on the focused window's
    /// display, the focused one first and then front to back, each in the
    /// cell `ArrangeGrid` gives it. With no focused window, the one in front
    /// counts as focused.
    private func arrange(_ action: ArrangeAction, focused: WindowRef?) throws(PlanError) {
        let screens = system.screens(), candidates = system.focusableWindows()
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

extension WindowCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try await context.windows.run(self)
    }
}
