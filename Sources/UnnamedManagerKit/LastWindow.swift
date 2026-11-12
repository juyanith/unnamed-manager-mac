/// Which of an app's windows Use Application brings forward (S-047): the
/// one the person used last, as macOS remembers it, so focusing an app
/// returns to where they were rather than to whatever window is on top.
/// The app reads the windows through Accessibility; this decides.
public enum LastWindow {
    public struct Candidate<ID: Equatable & Sendable>: Equatable, Sendable {
        public var id: ID
        public var isMinimized: Bool
        /// A document or browser window, not a panel, sheet or palette.
        public var isStandard: Bool
        public init(id: ID, isMinimized: Bool = false, isStandard: Bool = true) {
            self.id = id
            self.isMinimized = isMinimized
            self.isStandard = isStandard
        }
    }

    public struct Choice<ID: Equatable & Sendable>: Equatable, Sendable {
        public var id: ID
        /// The window is in the Dock and must come out of it first.
        public var unminimize: Bool
    }

    /// The app's focused window first, then its main window, then its
    /// frontmost standard window, then a minimized one. Nil when it has no
    /// windows, so activation alone decides (an app usually opens one).
    public static func pick<ID>(focused: ID?, main: ID?, windows: [Candidate<ID>]) -> Choice<ID>? {
        for id in [focused, main].compactMap({ $0 }) {
            if let window = windows.first(where: { $0.id == id }) {
                return Choice(id: id, unminimize: window.isMinimized)
            }
        }
        if let window = windows.first(where: { $0.isStandard && !$0.isMinimized }) {
            return Choice(id: window.id, unminimize: false)
        }
        if let window = windows.first(where: \.isStandard) {
            return Choice(id: window.id, unminimize: true)
        }
        return nil
    }
}
