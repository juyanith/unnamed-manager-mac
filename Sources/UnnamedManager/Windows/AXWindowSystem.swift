import AppKit
import ApplicationServices
import UnnamedManagerKit

/// Windows through Accessibility (S-062).
final class AXWindowSystem: WindowSystem {
    /// How long one Accessibility call may wait on an app that's busy.
    private static let timeout: Float = 0.25

    /// An AXUIElement as a dictionary key: the same window compares equal
    /// across calls.
    private struct Element: Hashable {
        let element: AXUIElement
        let pid: pid_t
        static func == (a: Element, b: Element) -> Bool { CFEqual(a.element, b.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    var canControlWindows: Bool { AXIsProcessTrusted() }

    func frontApp() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontApp(pid: app.processIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "The app in front")
    }

    func focusedWindow(of app: FrontApp) -> WindowRef? {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        let window: AXUIElement? = value(element, kAXFocusedWindowAttribute)
        return window.map { WindowRef(id: Element(element: $0, pid: app.pid)) }
    }

    func frame(of window: WindowRef) -> CGRect? {
        guard let window = window.id.base as? Element,
              let position: AXValue = value(window.element, kAXPositionAttribute),
              let size: AXValue = value(window.element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Size, then position, then size again: a window moving to a smaller
    /// display can only take its new size once it's there. Enhanced user
    /// interface (on while VoiceOver or some window tools run) makes apps
    /// such as Safari animate each step, so it's off while the window moves.
    func setFrame(_ frame: CGRect, of window: WindowRef) {
        guard let window = window.id.base as? Element else { return }
        let app = AXUIElementCreateApplication(window.pid)
        let enhanced: Bool = value(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer {
            if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
    }

    func screens() -> [WindowGeometry.Screen] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        return screens.map {
            WindowGeometry.Screen(frame: WindowGeometry.topLeft($0.frame, primaryHeight: primaryHeight),
                                  usable: WindowGeometry.topLeft($0.visibleFrame, primaryHeight: primaryHeight))
        }
    }

    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
