import Foundation

/// Whether Quit on Close quits an app after one of its windows closes
/// (S-086, spec v16). The app reads the facts; this decides.
public enum QuitOnClose {
    /// Apps never quit, whatever `windows.apps` says.
    public static let alwaysKept: Set<String> = ["com.apple.finder"]

    /// What the app knows about one running app once a window has closed.
    public struct App: Equatable, Sendable {
        /// Its bundle id, then those of the apps its bundle is inside, innermost first.
        public var bundleIds: [String]
        /// A menu bar or background app (`LSUIElement` or `LSBackgroundOnly`).
        public var isBackground: Bool
        /// It showed a window since it was first watched.
        public var hadWindow: Bool
        /// Windows it still has, minimized ones and ones on other Spaces included.
        public var windows: Int
        public var isHidden: Bool

        public init(bundleIds: [String], isBackground: Bool = false, hadWindow: Bool = true, windows: Int = 0, isHidden: Bool = false) {
            self.bundleIds = bundleIds
            self.isBackground = isBackground
            self.hadWindow = hadWindow
            self.windows = windows
            self.isHidden = isHidden
        }
    }

    /// True when the app should quit. `own` is this app's bundle id.
    public static func shouldQuit(_ app: App, settings: Config.Windows, own: String?) -> Bool {
        closedLast(app, settings: settings, own: own) && !isKept(app, settings: settings)
    }

    /// True when the window used before should get focus: the app stays
    /// open with no window left, as Finder does, and is still in front, so
    /// focus moves on as if it had quit.
    public static func focusesBefore(_ app: App, settings: Config.Windows, own: String?, isFrontmost: Bool) -> Bool {
        isFrontmost && closedLast(app, settings: settings, own: own) && isKept(app, settings: settings)
    }

    /// With Quit on Close on, the app closed its last window.
    private static func closedLast(_ app: App, settings: Config.Windows, own: String?) -> Bool {
        guard settings.quitOnClose, let id = app.bundleIds.first, id != own else { return false }
        return !app.isBackground && app.hadWindow && !app.isHidden && app.windows == 0
    }

    private static func isKept(_ app: App, settings: Config.Windows) -> Bool {
        app.bundleIds.contains { alwaysKept.contains($0) || settings.apps[$0]?.quit == false }
    }

    /// Whether Settings' Quit checkbox can change for an app.
    public static func canQuit(_ bundleId: String) -> Bool { !alwaysKept.contains(bundleId) }

    /// The apps a bundle is inside, innermost first: a helper app keeps the
    /// rule of the app it ships in.
    public static func containingApps(of bundle: URL) -> [URL] {
        var result: [URL] = []
        var url = bundle.standardizedFileURL.deletingLastPathComponent()
        while url.pathComponents.count > 1 {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame { result.append(url) }
            url = url.deletingLastPathComponent()
        }
        return result
    }
}
