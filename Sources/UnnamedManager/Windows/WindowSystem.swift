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
    /// A display's Spaces and the one on screen (S-097); nil when macOS doesn't say.
    func spaces(on screen: WindowGeometry.Screen) -> SpaceStrip?
    /// Where the pointer is, in the same coordinates as window frames.
    func pointerLocation() -> CGPoint?
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
