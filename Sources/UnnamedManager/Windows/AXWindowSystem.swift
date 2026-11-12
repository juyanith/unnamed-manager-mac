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

    func minimize(_ window: WindowRef) {
        guard let window = window.id.base as? Element else { return }
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    func screens() -> [WindowGeometry.Screen] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        return screens.map {
            WindowGeometry.Screen(frame: WindowGeometry.topLeft($0.frame, primaryHeight: primaryHeight),
                                  usable: WindowGeometry.topLeft($0.visibleFrame, primaryHeight: primaryHeight))
        }
    }

    /// Windows the window server shows on the current Spaces, matched to
    /// their apps' Accessibility windows by owner and frame.
    func focusableWindows() -> [WindowInfo] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var onScreen: [pid_t: [CGRect]] = [:]
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            onScreen[pid, default: []].append(frame)
        }
        var result: [WindowInfo] = []
        for (pid, frames) in onScreen {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.timeout)
            let windows: [AXUIElement] = value(app, kAXWindowsAttribute) ?? []
            for element in windows {
                let subrole: String? = value(element, kAXSubroleAttribute)
                let minimized: Bool = value(element, kAXMinimizedAttribute) ?? false
                guard subrole == kAXStandardWindowSubrole, !minimized else { continue }
                let ref = WindowRef(id: Element(element: element, pid: pid))
                guard let frame = frame(of: ref), frames.contains(where: { WindowGeometry.matches($0, frame) }) else { continue }
                result.append(WindowInfo(ref: ref, frame: frame, pid: pid))
            }
        }
        return result
    }

    /// Raises the window, makes it its app's focused window, then brings
    /// the app forward through NSWorkspace, which works from the background.
    func focus(_ window: WindowInfo) async throws(PlanError) {
        guard let element = window.ref.id.base as? Element,
              let running = NSRunningApplication(processIdentifier: window.pid) else { return }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element.element)
        AXUIElementSetAttributeValue(element.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element.element, kAXRaiseAction as CFString)
        guard let url = running.bundleURL else {
            running.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw PlanError("Couldn't focus \(running.localizedName ?? "the window"): \(error.localizedDescription)")
        }
    }

    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
