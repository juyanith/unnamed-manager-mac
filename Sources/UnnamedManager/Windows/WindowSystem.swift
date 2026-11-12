import CoreGraphics
import UnnamedManagerKit

/// One window, as a window system knows it. Equal for the same window
/// across calls, so Maximize can remember it.
struct WindowRef: Hashable {
    let id: AnyHashable
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
}

/// Carries out window commands on the focused window of the app in front,
/// and keeps what Maximize remembers (S-062).
final class WindowControl {
    let system: any WindowSystem
    private var maximized = MaximizeMemory<WindowRef>()

    init(system: any WindowSystem) {
        self.system = system
    }

    func run(_ command: WindowCommand) throws(PlanError) {
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
            let target = WindowGeometry.rect(fractions, in: screen.usable)
            system.setFrame(target, of: window)
            // A window with a minimum or maximum size keeps the edge it was placed against.
            if let actual = system.frame(of: window), !WindowGeometry.matches(actual, target) {
                system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: screen.usable), of: window)
            }
        }
    }
}

extension WindowCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try context.windows.run(self)
    }
}
