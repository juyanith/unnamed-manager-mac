import AppKit
import ApplicationServices
import UnnamedManagerKit

/// Brings an app's last focused window to the top of its windows through
/// Accessibility (S-047), so Use Application returns to the window the
/// person used last. LastWindow decides which; this reads and raises.
enum WindowRaiser {
    /// How long one Accessibility call may wait on an app that's busy.
    private static let timeout: Float = 0.25

    /// Raises the app's last focused window. False when there's nothing to
    /// raise or Accessibility isn't allowed; activation then decides alone.
    @discardableResult
    static func raiseLastFocused(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        let windows: [AXUIElement] = value(app, kAXWindowsAttribute) ?? []
        let candidates = windows.indices.map { index in
            let window = windows[index]
            let subrole: String? = value(window, kAXSubroleAttribute)
            return LastWindow.Candidate(id: index,
                                        isMinimized: value(window, kAXMinimizedAttribute) ?? false,
                                        isStandard: subrole == nil || subrole == kAXStandardWindowSubrole)
        }
        func index(of attribute: String) -> Int? {
            let element: AXUIElement? = value(app, attribute)
            return element.flatMap { element in windows.firstIndex { CFEqual($0, element) } }
        }
        guard let choice = LastWindow.pick(focused: index(of: kAXFocusedWindowAttribute),
                                           main: index(of: kAXMainWindowAttribute),
                                           windows: candidates) else { return false }
        let window = windows[choice.id]
        if choice.unminimize {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
