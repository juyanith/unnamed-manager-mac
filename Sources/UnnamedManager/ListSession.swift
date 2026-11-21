import UnnamedManagerKit

/// The list in the Guide (S-092 to S-095): the window behind each item,
/// the watch that takes out items whose windows closed, and what choosing
/// does. `Launcher` hands it the engine's side through closures.
final class ListSession {
    /// The windows Recent Windows lists and goes to: the ones the window
    /// actions use, so they share the focus history. The self-test replaces it.
    var windows: WindowControl?
    /// The window of each item in the list shown, by item id.
    private var listed: [Int: WindowRef] = [:]
    /// The list shown swaps with the chosen window instead of focusing it (S-095).
    private var swaps = false
    private var nextItemID = 1
    /// While a list is up, checks that its items' windows are still open.
    private var watch: Task<Void, Never>?

    init(windows: WindowControl?) { self.windows = windows }

    /// The items for a list that just opened, from the windows found now.
    /// Only the list just opened can be chosen from.
    func items(for menu: BindingNode) -> (front: ListItem?, items: [ListItem]) {
        listed = [:]
        swaps = menu.list?.swaps ?? false
        guard let list = menu.list, let windows else { return (nil, []) }
        let found = windows.recentWindows(list)
        func item(_ window: WindowControl.RecentWindow) -> ListItem {
            let id = nextItemID
            nextItemID += 1
            listed[id] = window.window.info.ref
            return ListItem(id: id, title: window.title, app: window.window.info.app, marks: window.marks)
        }
        let front = found.front.map(item)
        let items = found.items.map(item)
        GuideIcons.shared.load(Set(([front].compactMap { $0 } + items).compactMap { $0.app.map(IconSource.app) }))
        return (front, items)
    }

    /// Every 250 ms while a list is up, takes out the items whose windows
    /// closed: `remove` tells the engine. Stops once `items` is empty.
    func watchItems(_ items: @escaping () -> [ListItem], remove: @escaping (Int) -> Void) {
        guard watch == nil else { return }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let windows else { break }
                let shown = items()
                guard !shown.isEmpty else { break }
                for item in shown {
                    guard let ref = listed[item.id], !windows.exists(ref) else { continue }
                    remove(item.id)
                }
            }
            self?.watch = nil
        }
    }

    /// What choosing a list's item does: go to its window, or swap with it
    /// (S-092, S-095). Read at once, so a list opened before it runs
    /// doesn't change it. nil when the item has no window.
    func choice(for item: ListItem) -> (() async throws(PlanError) -> Void)? {
        guard let ref = listed[item.id], let windows else { return nil }
        let swaps = swaps
        return { () async throws(PlanError) in
            if swaps { try windows.swap(with: ref) } else { try await windows.choose(ref) }
        }
    }
}
