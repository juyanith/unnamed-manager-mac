import CoreGraphics
import UnnamedManagerKit

extension WindowControl {
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

    /// False once a listed window has closed or its app has quit.
    func exists(_ window: WindowRef) -> Bool { system.listed(window) != nil }
}
