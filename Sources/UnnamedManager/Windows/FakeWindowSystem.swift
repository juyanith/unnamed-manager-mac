import CoreGraphics
import UnnamedManagerKit

/// Windows kept in memory, for the self-test (S-062). Frames are in
/// top-left coordinates, as Accessibility reports them.
final class FakeWindowSystem: WindowSystem {
    struct Window {
        var frame: CGRect
        /// A window that won't grow past this, as an app with a maximum size.
        var maxSize: CGSize?
        var isMinimized = false
    }

    var app: FrontApp? = FrontApp(pid: 1, name: "TextEdit")
    var windows: [String: Window] = [:]
    var focused: String?
    var displays = [WindowGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          usable: CGRect(x: 0, y: 25, width: 1440, height: 875))]
    var canControlWindows = true

    func frontApp() -> FrontApp? { app }

    func focusedWindow(of app: FrontApp) -> WindowRef? {
        focused.map { WindowRef(id: $0) }
    }

    func frame(of window: WindowRef) -> CGRect? {
        (window.id.base as? String).flatMap { windows[$0]?.frame }
    }

    func setFrame(_ frame: CGRect, of window: WindowRef) {
        guard let id = window.id.base as? String, var window = windows[id] else { return }
        var size = frame.size
        if let maxSize = window.maxSize {
            size = CGSize(width: min(size.width, maxSize.width), height: min(size.height, maxSize.height))
        }
        window.frame = CGRect(origin: frame.origin, size: size)
        windows[id] = window
    }

    func minimize(_ window: WindowRef) {
        guard let id = window.id.base as? String else { return }
        windows[id]?.isMinimized = true
    }

    func screens() -> [WindowGeometry.Screen] { displays }
}
