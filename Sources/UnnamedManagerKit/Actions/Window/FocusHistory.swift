/// The windows that had focus, the most recent first, each once (S-083,
/// spec v13). Focus Window's and Swap Window's `recent` target reads it.
public struct FocusHistory<Window: Hashable> {
    /// The spec asks for at least 10.
    public static var limit: Int { 10 }

    public private(set) var windows: [Window] = []

    public init() {}

    /// Puts a window first, as it gets focus.
    public mutating func record(_ window: Window) {
        windows.removeAll { $0 == window }
        windows.insert(window, at: 0)
        if windows.count > Self.limit { windows.removeLast(windows.count - Self.limit) }
    }

    /// The window used before `focused`: the first one that isn't it and
    /// that `counts`, which says whether it still exists and can be picked.
    public func recent(before focused: Window?, where counts: (Window) -> Bool) -> Window? {
        windows.first { $0 != focused && counts($0) }
    }
}

extension FocusHistory: Sendable where Window: Sendable {}
