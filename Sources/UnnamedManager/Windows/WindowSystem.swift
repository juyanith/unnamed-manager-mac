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
    /// Its app's bundle id, which `windows.apps` names (spec v15).
    var app: String?
    /// A dialog, such as many apps' Settings windows: it takes focus, but
    /// stays out of Swap Window and Arrange Windows, as a small window does.
    var isDialog = false

    func isExcluded(by apps: Set<String>) -> Bool { app.map(apps.contains) ?? false }

    /// Left out by `windows.apps` for `rule`, or a dialog when the rule
    /// isn't Focus Window's.
    func isLeftOut(of rule: KeyPath<Config.Windows.AppRules, Bool>, apps: Set<String>) -> Bool {
        isExcluded(by: apps) || (isDialog && rule != \Config.Windows.AppRules.focus)
    }
}

/// A window Recent Windows can list (S-092): minimized, a hidden app's, or
/// on another Space too.
struct ListedWindow {
    let info: WindowInfo
    /// nil or empty when the window has none.
    let title: String?
    let appName: String
    let isMinimized: Bool
    /// Its app is hidden.
    let isHidden: Bool
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
    /// Brings a window and its app to the front with focus, moving to its Space.
    func focus(_ window: WindowInfo) async throws(PlanError)
    /// A window seen before, when it still exists, isn't minimized and its
    /// app isn't hidden, on any Space (S-083).
    func window(_ ref: WindowRef) -> WindowInfo?
    /// Calls `changed` with each window that gets focus, in any app, from now on (S-083).
    func watchFocus(_ changed: @escaping (WindowRef) -> Void)
    /// Goes to the Space to the left or right on a display, with no slide (S-088).
    func switchSpace(_ direction: SpaceDirection, on screen: WindowGeometry.Screen)
    /// Which desktop of its display a window is on (S-096).
    func desktop(of window: WindowRef) -> DesktopPlace
    /// Puts a window on desktop `number` of its display (S-096). With
    /// `follow` off, the desktop on screen is `from` again afterwards; with
    /// it, the fallback may already have gone there. Returns the desktop on
    /// screen afterwards. Fails when the window didn't move.
    func send(_ window: WindowRef, toDesktop number: Int, from: Int, follow: Bool) async throws(PlanError) -> Int
    /// A window seen before, when it still exists: minimized, hidden or on
    /// another Space too (S-092).
    func listed(_ ref: WindowRef) -> ListedWindow?
    /// Every standard window of every app that can be found now, minimized
    /// ones and hidden apps' too, without this app's own (S-092). Windows on
    /// other Spaces only when the app's window list has them.
    func allWindows() -> [ListedWindow]
    /// Brings back a minimized window and shows a hidden app, then focuses
    /// the window, moving to its Space (S-092).
    func restore(_ window: ListedWindow) async throws(PlanError)
}

/// Carries out window commands on the focused window of the app in front,
/// and keeps what Fill remembers (S-062) and which windows had focus (S-083).
final class WindowControl {
    let system: any WindowSystem
    private var filled = FillMemory<WindowRef>()
    private var history = FocusHistory<WindowRef>()

    /// The window settings: the gap (spec v3, v7) and Arrange Windows' limits (spec v8), read when an action runs.
    let settings: () -> Config.Windows
    private var gap: CGFloat { CGFloat(settings().gap).rounded() }

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
    private func recent(_ scope: WindowScope, around anchor: CGRect?, focused: WindowRef?, rule: KeyPath<Config.Windows.AppRules, Bool>, anySpace: Bool) -> WindowInfo? {
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

    /// Focuses a window and puts it first in the history.
    private func go(to window: WindowInfo) async throws(PlanError) {
        try await system.focus(window)
        history.record(window.ref)
    }

    /// A window as Recent Windows lists it (S-092): its title, or its app's
    /// name, and what the Guide marks.
    struct RecentWindow {
        let window: ListedWindow
        let title: String
        let marks: ListItem.Marks
    }

    /// Recent Windows (S-092, spec v18): the focused window, which Cancel
    /// shows, and the items: the windows Focus Window could pick for the
    /// list's filters, without the focused one, in the history's order,
    /// then the windows the history doesn't hold, the one in front first.
    /// At most `count`, and never a window of an app left out of Focus Window.
    /// A list that swaps (S-095, spec v19) has only shown windows on the
    /// current Space, and leaves out apps left out of Swap Window instead.
    func recentWindows(_ list: Config.List) -> (front: RecentWindow?, items: [RecentWindow]) {
        guard system.canControlWindows else { return (nil, []) }
        let focused = system.frontApp().flatMap { system.focusedWindow(of: $0) }
        // Swapping needs a focused window to trade places with (spec v19).
        if list.swaps && focused == nil { return (nil, []) }
        if let focused { history.record(focused) }
        let rule: KeyPath<Config.Windows.AppRules, Bool> = list.swaps ? \.swap : \.focus
        let here = system.focusableWindows(), screens = system.screens(), excluded = settings().leftOut(of: rule)
        let onSpace = Set(here.map(\.ref))
        let all = system.allWindows()
        let found = Dictionary(all.map { ($0.info.ref, $0) }, uniquingKeysWith: { first, _ in first })
        let front = focused.flatMap { found[$0] ?? system.listed($0) }
        let display = (front?.info.frame ?? here.first?.frame).flatMap { WindowGeometry.screen(for: $0, among: screens) }
        func recent(_ window: ListedWindow) -> RecentWindow {
            var marks: ListItem.Marks = []
            if window.isMinimized { marks.insert(.minimized) }
            if window.isHidden { marks.insert(.hidden) }
            if !window.isMinimized && !window.isHidden && !onSpace.contains(window.info.ref) { marks.insert(.otherSpace) }
            if let display, WindowGeometry.screen(for: window.info.frame, among: screens) != display { marks.insert(.otherDisplay) }
            let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? window.appName
            return RecentWindow(window: window, title: title, marks: marks)
        }
        // History entries that closed are left out here, so they never take an item's place.
        var listed = found
        let used = history.windows.filter { ref in
            if listed[ref] == nil { listed[ref] = system.listed(ref) }
            return listed[ref] != nil
        }
        // A window on screen that the app list missed is still listed.
        for ref in here.map(\.ref) where listed[ref] == nil { listed[ref] = system.listed(ref) }
        var items: [WindowRef: RecentWindow] = [:]
        let refs = RecentWindows.items(history: used, front: here.map(\.ref), found: all.map(\.info.ref),
                                       focused: focused, count: list.count) { ref in
            guard let window = listed[ref], !window.info.isLeftOut(of: rule, apps: excluded) else { return false }
            let item = recent(window)
            if !list.includesMinimized && item.marks.contains(.minimized) { return false }
            if !list.includesHidden && item.marks.contains(.hidden) { return false }
            if list.currentSpaceOnly && item.marks.contains(.otherSpace) { return false }
            if list.displayOnly && item.marks.contains(.otherDisplay) { return false }
            items[ref] = item
            return true
        }
        return (front.map(recent), refs.compactMap { items[$0] })
    }

    /// Goes to a window chosen in Recent Windows (S-092). It's first in the
    /// history at once, before macOS reports the focus change, so the list
    /// opened right away has the window before it first.
    func choose(_ window: WindowRef) async throws(PlanError) {
        guard let listed = system.listed(window) else {
            throw PlanError("That window has closed.", alerts: true)
        }
        history.record(window)
        try await system.restore(listed)
    }

    /// Trades places with a window chosen in a list that swaps (S-095,
    /// spec v19), as Swap Window does: focus stays, and the history doesn't
    /// change, so choosing again right away swaps the two back.
    func swap(with window: WindowRef) throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to move windows.")
        }
        guard let app = system.frontApp(), let focused = system.focusedWindow(of: app),
              let frame = system.frame(of: focused) else {
            throw PlanError("No window to swap with.", alerts: true)
        }
        try checkSwaps(focused, app: app)
        guard let other = system.frame(of: window) else {
            throw PlanError("That window has closed.", alerts: true)
        }
        put(focused, in: other)
        put(window, in: frame)
    }

    /// Send to Space (S-096, spec v20): puts the focused window on another
    /// desktop of its display. With `follow`, focus goes with it to that
    /// Space; without, it goes to the window used before on this one, so
    /// typing never goes to a window you can't see. The history keeps the
    /// sent window, so Window Used Before can go back to it.
    func send(to target: SpaceTarget, follow: Bool) async throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to move windows.")
        }
        guard let app = system.frontApp(), let window = system.focusedWindow(of: app), let frame = system.frame(of: window) else {
            throw PlanError("No window to send.", alerts: true)
        }
        history.record(window)
        let place = system.desktop(of: window)
        switch SpaceSend.pick(target, from: place, appName: app.name) {
        case let .none(failure):
            throw PlanError(failure, alerts: true)
        case .stay:
            return
        case let .desktop(number):
            guard case let .desktop(from, _) = place else { return }
            let onScreen = try await system.send(window, toDesktop: number, from: from, follow: follow)
            if follow, onScreen != number { await swipe(from: onScreen, to: number, around: frame) }
        }
        if follow {
            if let sent = system.window(window) { try await go(to: sent) }
        } else if let other = recent(.display, around: frame, focused: window, rule: \.focus, anySpace: false) {
            try await go(to: other)
        }
    }

    /// Goes with a sent window by Switch Space's swipe, one Space at a time,
    /// so there's no slide and no Switch to Desktop shortcut is needed. Focus
    /// alone would slide, or leave you behind when the Dock's “switch to a
    /// Space with open windows” is off.
    private func swipe(from: Int, to number: Int, around frame: CGRect) async {
        guard let screen = WindowGeometry.screen(for: frame, among: system.screens()) else { return }
        for step in 0..<abs(number - from) {
            if step > 0 { try? await Task.sleep(for: Self.swipeGap) }
            system.switchSpace(number > from ? .right : .left, on: screen)
        }
    }

    /// Between swipes, so the Dock takes each one.
    private static let swipeGap = Duration.milliseconds(60)

    /// False once a listed window has closed or its app has quit.
    func exists(_ window: WindowRef) -> Bool { system.listed(window) != nil }

    /// Focus Window (S-068, S-069, S-072, S-073, S-078, S-079, S-082, S-083).
    /// Finding no window plays the alert sound (spec v10).
    private func focus(_ target: WindowTarget, scope: WindowScope, from focused: WindowRef?) async throws(PlanError) {
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
    private func checkSwaps(_ window: WindowRef, app: FrontApp) throws(PlanError) {
        guard let info = system.window(window) else { return }
        if info.isDialog { throw PlanError("A dialog is left out of Swap Window.", alerts: true) }
        if info.isExcluded(by: settings().leftOut(of: \.swap)) {
            throw PlanError("\(app.name) is left out of Swap Window.", alerts: true)
        }
    }

    /// Swap Window (S-077): the focused window and the one `target` names
    /// trade frames, and focus stays. Finding no window plays the alert
    /// sound (spec v10). The window used before must be on this Space (S-083).
    private func swap(_ window: WindowRef, at frame: CGRect, with target: WindowTarget, scope: WindowScope) throws(PlanError) {
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
    /// Apps with `"arrange": false` in `windows.apps` are never counted or
    /// moved (S-084, spec v15); when the focused window is one of theirs, its display is
    /// still the one arranged, and the window in front there counts as focused.
    private func arrange(_ action: ArrangeAction, focused: WindowRef?) throws(PlanError) {
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

extension WindowCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try await context.windows.run(self)
    }
}
