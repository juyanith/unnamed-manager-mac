import CoreGraphics
import UnnamedManagerKit
/// Carries out window commands on the focused window of the app in front,
/// and keeps what Fill remembers (S-062) and which windows had focus (S-083).
final class WindowControl {
    let system: any WindowSystem
    private var filled = FillMemory<WindowRef>()
    /// Which windows had focus, for Window Used Before and Recent Windows.
    var history = FocusHistory<WindowRef>()

    /// The window settings: the gap (spec v3, v7) and Arrange Windows' limits (spec v8), read when an action runs.
    let settings: () -> Config.Windows
    var gap: CGFloat { CGFloat(settings().gap).rounded() }

    init(system: any WindowSystem, settings: @escaping () -> Config.Windows = { Config.Windows() }) {
        self.system = system
        self.settings = settings
        system.watchFocus { [weak self] in self?.history.record($0) }
    }

    func run(_ command: WindowCommand) async throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to move windows.")
        }
        let app = system.frontApp()
        let focused = app.flatMap { system.focusedWindow(of: $0) }
        // In case the focus change wasn't reported, as for a window that got focus before the app started.
        if let focused { history.record(focused) }
        // Focus Window and Arrange Windows also work with no focused window.
        switch command {
        case let .focus(target, scope):
            try await focus(target, scope: scope, from: focused)
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
            // Swap Window never moves a left-out app's window, the focused one included (spec v15).
            try checkSwaps(window, app: app)
            try swap(window, at: frame, with: target, scope: scope)
        case .focus, .arrange:
            break
        }
    }

    /// Focuses a window and puts it first in the history.
    func go(to window: WindowInfo) async throws(PlanError) {
        try await system.focus(window)
        history.record(window.ref)
    }

    /// Gives a window another's frame as it is. One that won't take the
    /// size keeps the edge on the usable area's edge, a gap in, as with Place Window.
    func put(_ window: WindowRef, in target: CGRect) {
        system.setFrame(target, of: window)
        guard let actual = system.frame(of: window), !WindowGeometry.matches(actual, target),
              let screen = WindowGeometry.screen(for: target, among: system.screens()) else { return }
        system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: screen.usable.insetBy(dx: gap, dy: gap)), of: window)
    }

    /// Puts a window in `frame` on a screen, with the gap around it.
    func place(_ window: WindowRef, in frame: CGRect, on screen: WindowGeometry.Screen) {
        let gap = gap
        let target = WindowGeometry.withGap(frame, in: screen.usable, gap: gap)
        system.setFrame(target, of: window)
        // A window with a minimum or maximum size keeps the edge it was placed against, a gap in from the screen's.
        if let actual = system.frame(of: window), !WindowGeometry.matches(actual, target) {
            let inside = screen.usable.insetBy(dx: gap, dy: gap)
            system.setFrame(WindowGeometry.anchored(actual.size, to: target, in: inside), of: window)
        }
    }
}

extension WindowCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try await context.windows.run(self)
    }
}
