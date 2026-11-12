import AppKit
import SwiftUI
import UnnamedManagerKit

/// The panel that holds the Guide. Non-activating and never key, so the
/// app in front keeps its focus; keys come from the event tap, not here.
final class GuidePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the hosted view reads, so a flash can animate in place.
@Observable
final class GuideModel {
    var content = GuideContent.placeholder
    var isFlashing = false
}

private struct GuideHost: View {
    let model: GuideModel

    var body: some View {
        GuideView(content: model.content, isFlashing: model.isFlashing)
    }
}

/// Shows, updates, flashes and hides the Guide. The panel is made the first
/// time it's needed, so with showHud off no panel ever exists (S-021).
final class GuideController {
    private let model = GuideModel()
    private var made: (panel: GuidePanel, host: NSHostingView<GuideHost>)?
    private(set) var content: GuideContent?
    /// Whether the Guide is meant to be up. Kept separately from the panel,
    /// because a fade doesn't finish while the display is asleep.
    private var isShown = false

    /// Where on the screen the Guide goes (ui.position).
    var position: GuidePlacement.Position = .center

    /// The Guide's look (ui.theme, S-020): "system" follows the Mac, "light"
    /// and "dark" fix it. Only the Guide; windows always follow the Mac.
    var theme = "system" {
        didSet { made?.panel.appearance = Self.appearance(for: theme) }
    }

    static func appearance(for theme: String) -> NSAppearance? {
        switch theme.lowercased() {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    /// True once a panel exists.
    var hasPanel: Bool { made != nil }
    var isVisible: Bool { isShown && (made?.panel.isVisible ?? false) }
    var window: NSWindow { parts.panel }

    private var parts: (panel: GuidePanel, host: NSHostingView<GuideHost>) {
        if let made { return made }
        let panel = GuidePanel()
        panel.appearance = Self.appearance(for: theme)
        let host = NSHostingView(rootView: GuideHost(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        made = (panel, host)
        return (panel, host)
    }

    func show(_ content: GuideContent) {
        let (panel, host) = parts
        let wasVisible = isVisible
        isShown = true
        self.content = content
        model.content = content
        model.isFlashing = false
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        if !wasVisible, let screen = Self.frontScreen() ?? NSScreen.main {
            // Placed once per sequence, so the Guide doesn't jump between menus.
            panel.setFrameOrigin(GuidePlacement.origin(size: size, in: screen.visibleFrame, position: position))
        } else if wasVisible {
            // Keep the top edge still while the size changes.
            let top = panel.frame.maxY
            panel.setFrameOrigin(NSPoint(x: (panel.frame.midX - size.width / 2).rounded(), y: top - size.height))
        }
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            fade(to: 1)
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: content.announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Outlines the Guide in the accent for a moment (S-018).
    func flash() {
        guard isVisible else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(Motion.errorFlash(reduceMotion)) { model.isFlashing = true }
        Task { [model] in
            try? await Task.sleep(for: Motion.errorFlashHold)
            withAnimation(Motion.errorFlash(reduceMotion)) { model.isFlashing = false }
        }
    }

    /// True while the flash is showing, for the self-test and snapshots.
    var isFlashing: Bool { model.isFlashing }

    /// Holds the flash on, so a snapshot can capture it.
    func holdFlashForSnapshot(_ on: Bool) {
        model.isFlashing = on
    }

    /// Shows why an action failed for Motion.errorMessageHold, then closes (S-015).
    func showFailure(_ message: String, title: String) {
        let content = GuideContent(path: [title], rows: [], cancelKey: "", backKey: nil, failure: message)
        show(content)
        let shown = content
        Task { [weak self] in
            try? await Task.sleep(for: Motion.errorMessageHold)
            // Only close it if nothing newer took its place.
            if self?.content == shown { self?.hide() }
        }
    }

    func hide() {
        guard isShown, let panel = made?.panel else { return }
        isShown = false
        content = nil
        fade(to: 0)
        // Order out after the fade by the clock, not the animation's
        // completion, which never comes while the display is asleep.
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.guideFadeSeconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                panel.orderOut(nil)
                panel.alphaValue = 0
            }
        }
    }

    /// The screen that holds the front app's key window: its frontmost
    /// normal window in the window list, which is ordered front to back.
    static func frontScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let info = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                                                && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo),
              let primary = NSScreen.screens.first else { return nil }
        let window = GuidePlacement.appKitRect(fromWindowList: bounds, primaryScreenHeight: primary.frame.height)
        let screens = NSScreen.screens
        return GuidePlacement.screen(for: window, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// A fade from Motion; instant under Reduce Motion.
    private func fade(to alpha: CGFloat) {
        guard let panel = made?.panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.guideFadeSeconds
            panel.animator().alphaValue = alpha
        }
    }
}
