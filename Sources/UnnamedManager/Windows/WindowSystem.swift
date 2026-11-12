import CoreGraphics
import UnnamedManagerKit

/// One window, as a window system knows it. Equal for the same window
/// across calls, so Maximize can remember it.
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
    /// Space of every display, without this app's own (S-068).
    func focusableWindows() -> [WindowInfo]
    /// Brings a window and its app to the front with focus.
    func focus(_ window: WindowInfo) async throws(PlanError)
}

/// Carries out window commands on the focused window of the app in front,
/// and keeps what Maximize remembers (S-062).
final class WindowControl {
    let system: any WindowSystem
    private var maximized = MaximizeMemory<WindowRef>()

    /// The gap Place Window leaves around windows (spec v3), read when an action runs.
    let gap: () -> Double

    init(system: any WindowSystem, gap: @escaping () -> Double = { Config.Windows().gap }) {
        self.system = system
        self.gap = gap
    }

    func run(_ command: WindowCommand) async throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to move windows.")
        }
        guard let app = system.frontApp() else { throw PlanError("No app is in front.") }
        guard let window = system.focusedWindow(of: app), let frame = system.frame(of: window) else {
            throw PlanError("\(app.name) has no window to \(command.verb).")
        }
        guard let screen = WindowGeometry.screen(for: frame, among: system.screens()) else { return }
        switch command {
        case let .maximize(toggle):
            switch maximized.step(for: window, frame: frame, usable: screen.usable, toggle: toggle) {
            case let .fill(usable):
                system.setFrame(usable, of: window)
                maximized.record(window, before: frame, after: system.frame(of: window) ?? usable)
            case let .restore(before):
                system.setFrame(before, of: window)
            case .stay:
                break
            }
        case .minimize:
            system.minimize(window)
        case let .place(fractions):
            let gap = CGFloat(gap()).rounded()
            let target = WindowGeometry.withGap(WindowGeometry.rect(fractions, in: screen.usable), in: screen.usable, gap: gap)
            system.setFrame(target, of: window)
            // A window with a minimum or maximum size keeps the edge it was placed against, a gap in from the screen's.
            if let actual = system.frame(of: window), !WindowGeometry.matches(actual, target) {
                let inside = screen.usable.insetBy(dx: gap, dy: gap)
                system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: inside), of: window)
            }
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
        case let .focus(direction) where direction == .next || direction == .previous:
            let windows = system.focusableWindows()
            let order = WindowGeometry.cycleOrder(windows.map(\.frame), owners: windows.map(\.pid), screens: system.screens())
            guard let index = WindowGeometry.step(from: windows.firstIndex { $0.ref == window }, in: order, direction) else {
                throw PlanError(command.failure ?? "")
            }
            try await system.focus(windows[index])
        case let .focus(direction):
            let others = system.focusableWindows().filter { $0.ref != window }
            guard let index = WindowGeometry.neighbor(of: frame, direction, among: others.map(\.frame)) else {
                throw PlanError(command.failure ?? "")
            }
            try await system.focus(others[index])
        }
    }
}

extension WindowCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try await context.windows.run(self)
    }
}
