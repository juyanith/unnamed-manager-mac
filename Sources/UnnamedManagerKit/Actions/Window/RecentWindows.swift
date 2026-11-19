/// Which windows Recent Windows lists, in which order (S-092, spec v18).
public enum RecentWindows {
    /// The windows in `history` first, most recent first, then the windows
    /// it doesn't hold: those in `front` (front to back) first, then the
    /// rest of `found` in their order. A window in `front` is listed even
    /// when `found` doesn't hold it, so every window Focus Window can reach
    /// is one Recent Windows can list. Never `focused`, each window once,
    /// only those `keep` takes, at most `count`.
    public static func items<Window: Hashable>(history: [Window], front: [Window], found: [Window], focused: Window?,
                                               count: Int, keep: (Window) -> Bool) -> [Window] {
        let depth = Dictionary(front.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(found)
        let rest = (found + front.filter { !known.contains($0) }).enumerated()
            .sorted { (depth[$0.element] ?? front.count, $0.offset) < (depth[$1.element] ?? front.count, $1.offset) }
            .map(\.element)
        var seen: Set<Window> = focused.map { [$0] } ?? []
        var items: [Window] = []
        for window in history + rest where items.count < count {
            if seen.insert(window).inserted, keep(window) { items.append(window) }
        }
        return items
    }
}
