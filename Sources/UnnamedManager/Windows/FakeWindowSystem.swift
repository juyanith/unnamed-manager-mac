import CoreGraphics
import UnnamedManagerKit

/// Windows kept in memory, for the self-test (S-062). Frames are in
/// top-left coordinates, as Accessibility reports them.
final class FakeWindowSystem: WindowSystem {
    struct Window {
        var frame: CGRect
        /// A window that won't grow past this, as an app with a maximum size.
        var maxSize: CGSize?
        /// A window that won't shrink past this.
        var minSize: CGSize?
        var isMinimized = false
        /// A window that never changes size, such as a dialog.
        var isFixedSize = false
        var pid: pid_t = 1
        var app: String?
        /// Its Space (S-083); only the current Space's windows show.
        var space = 1
        var title: String?
        /// Its app is hidden (S-092).
        var isHidden = false
        /// In a full-screen Space, or on every Space (S-096).
        var place: Place = .desktop
        /// On screen, but missing from the list of every app's windows, as a
        /// menu bar app's Settings window once was.
        var isUnlisted = false
        /// A dialog, such as a Settings window: it takes focus, but isn't swapped or arranged.
        var isDialog = false
    }

    enum Place { case desktop, fullScreen, everySpace }

    /// Each Send to Space: the window, the desktop it went to, and whether you went too (S-096).
    private(set) var sends: [(id: String, desktop: Int, follow: Bool)] = []
    /// The platform refuses every send, as macOS may.
    var refusesSend = false

    /// Each window Recent Windows restored, in order (S-092).
    private(set) var restored: [String] = []

    var app: FrontApp? = FrontApp(pid: 1, name: "TextEdit")
    var windows: [String: Window] = [:]
    var focused: String?
    /// Window ids from the front to the back; windows not listed come after, by id.
    var stacking: [String] = []
    var displays = [WindowGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          usable: CGRect(x: 0, y: 25, width: 1440, height: 875))]
    var canControlWindows = true
    var currentSpace = 1
    /// Spaces go from 1 to this one, left to right (S-088).
    var lastSpace = 3
    /// Spaces that are full-screen apps, which numbers don't count (S-097).
    var fullScreenSpaces: Set<Int> = []
    /// Nil when macOS doesn't say where the pointer is.
    var pointer: CGPoint? = CGPoint(x: 700, y: 400)
    /// Each Switch Space, with the display it went to.
    var spaceSwitches: [(direction: SpaceDirection, screen: CGRect)] = []
    private var focusChanged: ((WindowRef) -> Void)?

    func frontApp() -> FrontApp? { app }

    func focusedWindow(of app: FrontApp) -> WindowRef? {
        focused.map { WindowRef(id: $0) }
    }

    func frame(of window: WindowRef) -> CGRect? {
        (window.id.base as? String).flatMap { windows[$0]?.frame }
    }

    func setFrame(_ frame: CGRect, of window: WindowRef) {
        guard let id = window.id.base as? String, var window = windows[id] else { return }
        var size = window.isFixedSize ? window.frame.size : frame.size
        if let maxSize = window.maxSize {
            size = CGSize(width: min(size.width, maxSize.width), height: min(size.height, maxSize.height))
        }
        if let minSize = window.minSize {
            size = CGSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))
        }
        window.frame = CGRect(origin: frame.origin, size: size)
        windows[id] = window
    }

    func minimize(_ window: WindowRef) {
        guard let id = window.id.base as? String else { return }
        windows[id]?.isMinimized = true
    }

    func screens() -> [WindowGeometry.Screen] { displays }

    func focusableWindows() -> [WindowInfo] {
        func depth(_ id: String) -> Int { stacking.firstIndex(of: id) ?? stacking.count }
        return windows.filter { !$0.value.isMinimized && !$0.value.isHidden && $0.value.space == currentSpace }
            .sorted { (depth($0.key), $0.key) < (depth($1.key), $1.key) }
            .map { info($0.key, $0.value) }
    }

    private func info(_ id: String, _ window: Window) -> WindowInfo {
        WindowInfo(ref: WindowRef(id: id), frame: window.frame, pid: window.pid, app: window.app, isDialog: window.isDialog)
    }

    /// Focusing raises the window to the front and brings its Space, as the real one does.
    func focus(_ window: WindowInfo) async throws(PlanError) {
        guard let id = window.ref.id.base as? String else { return }
        raise(id)
    }

    func window(_ ref: WindowRef) -> WindowInfo? {
        guard let id = ref.id.base as? String, let window = windows[id], !window.isMinimized, !window.isHidden else { return nil }
        return info(id, window)
    }

    func listed(_ ref: WindowRef) -> ListedWindow? {
        guard let id = ref.id.base as? String, let window = windows[id] else { return nil }
        // "com.apple.Terminal" is Terminal.
        let appName = window.app.flatMap { $0.split(separator: ".").last.map(String.init) } ?? "App"
        return ListedWindow(info: info(id, window), title: window.title, appName: appName,
                            isMinimized: window.isMinimized, isHidden: window.isHidden)
    }

    /// As the real one: the current Space's windows, and minimized and hidden ones.
    func allWindows() -> [ListedWindow] {
        windows.keys.sorted().filter { id in
            let window = windows[id]!
            return !window.isUnlisted && (window.space == currentSpace || window.isMinimized || window.isHidden)
        }.compactMap { listed(WindowRef(id: $0)) }
    }

    func restore(_ window: ListedWindow) async throws(PlanError) {
        guard let id = window.info.ref.id.base as? String else { return }
        windows[id]?.isMinimized = false
        windows[id]?.isHidden = false
        restored.append(id)
        raise(id)
    }

    func watchFocus(_ changed: @escaping (WindowRef) -> Void) {
        focusChanged = changed
    }

    /// Stops at the first and last Space, as the Dock does.
    func switchSpace(_ direction: SpaceDirection, on screen: WindowGeometry.Screen) {
        spaceSwitches.append((direction, screen.frame))
        currentSpace = min(max(currentSpace + (direction == .right ? 1 : -1), 1), lastSpace)
    }

    func spaces(on screen: WindowGeometry.Screen) -> SpaceStrip? {
        SpaceStrip(desktops: (1...lastSpace).map { !fullScreenSpaces.contains($0) }, current: currentSpace - 1)
    }

    func pointerLocation() -> CGPoint? { pointer }

    func desktop(of window: WindowRef) -> DesktopPlace {
        guard let id = window.id.base as? String, let window = windows[id] else { return .unknown }
        switch window.place {
        case .desktop: return .desktop(window.space, of: lastSpace)
        case .fullScreen: return .fullScreen
        case .everySpace: return .everySpace
        }
    }

    /// The window goes to that desktop; the Space on screen doesn't change,
    /// as with the window server's quiet move.
    func send(_ window: WindowRef, toDesktop number: Int, from: Int, follow: Bool) async throws(PlanError) -> Int {
        guard !refusesSend else { throw PlanError("macOS didn't move the window.", alerts: true) }
        guard let id = window.id.base as? String else { return from }
        windows[id]?.space = number
        sends.append((id, number, follow))
        return from
    }

    /// A click on a window: it takes focus, as reported to `watchFocus`.
    func click(_ id: String) {
        raise(id)
        focusChanged?(WindowRef(id: id))
    }

    private func raise(_ id: String) {
        focused = id
        currentSpace = windows[id]?.space ?? currentSpace
        stacking.removeAll { $0 == id }
        stacking.insert(id, at: 0)
    }
}
