import CoreGraphics
import UnnamedManagerKit

extension WindowControl {
    /// A window Focus Window and Swap Window can pick, and what of it shows.
    private struct Candidate {
        let info: WindowInfo
        let seen: SeenWindow
    }

    /// Focus Window's candidates (S-068), front to back: the windows you can
    /// see, and the focused one (S-082, spec v12), but none of an app in
    /// whose `rule` in `windows.apps` is false (S-083, spec v15): `\.focus`
    /// for Focus Window, `\.swap` for Swap Window. Windows on every display
    /// hide the ones behind them, left-out ones too. With `"scope": "display"`,
    /// only those on the display of `anchor`, or of the window in front
    /// without one (S-078).
    private func candidates(_ scope: WindowScope, around anchor: CGRect?, focused: WindowRef?, rule: KeyPath<Config.Windows.AppRules, Bool>) -> [Candidate] {
        let windows = system.focusableWindows()
        let parts = WindowGeometry.visibleParts(windows.map(\.frame))
        let square = CGFloat(settings().minVisible), excluded = settings().leftOut(of: rule)
        let seen = windows.indices.compactMap { index -> Candidate? in
            let window = windows[index]
            guard !window.isLeftOut(of: rule, apps: excluded),
                  window.ref == focused || WindowGeometry.shows(parts[index], square: square) else { return nil }
            return Candidate(info: window, seen: SeenWindow(frame: window.frame, parts: parts[index], owner: window.pid))
        }
        guard scope == .display, let anchor = anchor ?? seen.first?.info.frame else { return seen }
        let screens = system.screens()
        let screen = WindowGeometry.screen(for: anchor, among: screens)
        return seen.filter { WindowGeometry.screen(for: $0.info.frame, among: screens) == screen }
    }

    /// The window used before (S-083, spec v13): the first in the history
    /// that still exists and isn't the focused one or a left-out app's, on
    /// the scope's display. Focus Window's can be on another Space, Swap
    /// Window's can't. With none, the front-most other window.
    func recent(_ scope: WindowScope, around anchor: CGRect?, focused: WindowRef?, rule: KeyPath<Config.Windows.AppRules, Bool>, anySpace: Bool) -> WindowInfo? {
        let here = system.focusableWindows(), screens = system.screens(), excluded = settings().leftOut(of: rule)
        let display = scope == .display ? (anchor ?? here.first?.frame).flatMap { WindowGeometry.screen(for: $0, among: screens) } : nil
        func counts(_ window: WindowInfo) -> Bool {
            window.ref != focused && !window.isLeftOut(of: rule, apps: excluded)
                && (display == nil || WindowGeometry.screen(for: window.frame, among: screens) == display)
        }
        let onSpace = Set(here.map(\.ref))
        let used = history.recent(before: focused) { ref in
            (anySpace || onSpace.contains(ref)) && system.window(ref).map(counts) == true
        }
        return used.flatMap(system.window) ?? here.first(where: counts)
    }

    /// Focus Window (S-068, S-069, S-072, S-073, S-078, S-079, S-082, S-083).
    /// Finding no window plays the alert sound (spec v10).
    func focus(_ target: WindowTarget, scope: WindowScope, from focused: WindowRef?) async throws(PlanError) {
        let frame = focused.flatMap { system.frame(of: $0) }
        if target == .window(.recent) {
            guard let window = recent(scope, around: frame, focused: focused, rule: \.focus, anySpace: true) else {
                throw PlanError(focused == nil ? "No window to focus." : FocusDirection.recent.failure, alerts: true)
            }
            try await go(to: window)
            return
        }
        let candidates = candidates(scope, around: frame, focused: focused, rule: \.focus)
        let windows = candidates.map(\.info)
        let order = WindowGeometry.cycleOrder(candidates.map(\.seen), screens: system.screens(), settings: settings())
        // First, Last and numbers don't need a focused window, and stay on a window that's already there (S-073, S-079).
        let direction: FocusDirection
        switch target {
        case .window(.first), .window(.last), .number:
            guard let place = Self.place(of: target, in: order) else {
                if case let .number(number) = target, !order.isEmpty {
                    throw PlanError(WindowTarget.pastTheEnd(number, count: order.count), alerts: true)
                }
                throw PlanError("No window to focus.", alerts: true)
            }
            if windows[place].ref != focused { try await go(to: windows[place]) }
            return
        case let .window(word):
            direction = word
        }
        // With no focused window, any other direction goes to the window in front of the others (S-072, spec v5).
        guard let frame else {
            guard let top = windows.first else { throw PlanError("No window to focus.", alerts: true) }
            try await go(to: top)
            return
        }
        if direction == .next || direction == .previous {
            guard let index = WindowGeometry.step(from: windows.firstIndex { $0.ref == focused }, in: order, direction) else {
                throw PlanError(direction.failure, alerts: true)
            }
            try await go(to: windows[index])
            return
        }
        let others = candidates.filter { $0.info.ref != focused }
        guard let index = WindowGeometry.neighbor(of: frame, direction, among: others.map(\.seen), settings: settings()) else {
            throw PlanError(direction.failure, alerts: true)
        }
        try await go(to: others[index].info)
    }

    /// The window First, Last or a number names in the order; nil past its end.
    private static func place(of target: WindowTarget, in order: [Int]) -> Int? {
        switch target {
        case .window(.first): order.first
        case .window(.last): order.last
        case let .number(number): number <= order.count ? order[number - 1] : nil
        case .window: nil
        }
    }

    /// Swap Window never moves a left-out app's window or a dialog, the
    /// focused one included (spec v15).
    func checkSwaps(_ window: WindowRef, app: FrontApp) throws(PlanError) {
        guard let info = system.window(window) else { return }
        if info.isDialog { throw PlanError("A dialog is left out of Swap Window.", alerts: true) }
        if info.isExcluded(by: settings().leftOut(of: \.swap)) {
            throw PlanError("\(app.name) is left out of Swap Window.", alerts: true)
        }
    }

    /// Swap Window (S-077): the focused window and the one `target` names
    /// trade frames, and focus stays. Finding no window plays the alert
    /// sound (spec v10). The window used before must be on this Space (S-083).
    func swap(_ window: WindowRef, at frame: CGRect, with target: WindowTarget, scope: WindowScope) throws(PlanError) {
        if target == .window(.recent) {
            guard let other = recent(scope, around: frame, focused: window, rule: \.swap, anySpace: false) else {
                throw PlanError(FocusDirection.recent.failure, alerts: true)
            }
            put(window, in: other.frame)
            put(other.ref, in: frame)
            return
        }
        let windows = candidates(scope, around: frame, focused: window, rule: \.swap)
        switch WindowGeometry.swapPartner(target, current: windows.firstIndex { $0.info.ref == window }, frame: frame,
                                          windows: windows.map(\.seen), screens: system.screens(), settings: settings()) {
        case let .none(failure):
            throw PlanError(failure, alerts: true)
        case .stay:
            break
        case let .window(index):
            let other = windows[index].info
            put(window, in: other.frame)
            put(other.ref, in: frame)
        }
    }
}
