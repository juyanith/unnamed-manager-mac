import AppKit
import ApplicationServices
import UnnamedManagerKit

/// Quits an app when its last window closes (S-086, spec v16). While
/// `windows.quitOnClose` is on, each app with a Dock icon gets an
/// Accessibility observer for its windows opening and closing.
/// `windows.quitOnCloseDelayMs` after one closes, the app's windows are counted again, and
/// `QuitOnClose` decides: quit it, or, when it's kept open and still in
/// front, focus the window used before. Windows on another Space aren't in an app's
/// window list, so every window seen is kept, and counts while its
/// element still answers (as for S-083).
final class QuitOnCloseWatcher {
    /// What's known about one watched app.
    private struct Watched {
        let observer: AXObserver
        let app: AXUIElement
        var windows: [AXUIElement] = []
        var hadWindow = false
    }

    /// How long one Accessibility call may wait on a busy app.
    private static let timeout: Float = 0.25

    private let store: ConfigStore
    /// Focus Window to the window used before (S-083).
    private let focusBefore: () async -> Void
    private var watched: [pid_t: Watched] = [:]
    private var checks: [pid_t: Task<Void, Never>] = [:]
    private var tokens: [any NSObjectProtocol] = []
    private var settings: Config.Windows { store.loaded?.config.windows ?? Config.Windows() }

    init(store: ConfigStore, focusBefore: @escaping () async -> Void) {
        self.store = store
        self.focusBefore = focusBefore
        follow()
    }

    isolated deinit {
        stop()
    }

    /// Starts or stops with the setting, now and each time it changes.
    private func follow() {
        let isOn = withObservationTracking { settings.quitOnClose } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        if isOn, tokens.isEmpty { start() } else if !isOn, !tokens.isEmpty { stop() }
    }

    private func start() {
        log.info("Quit on Close is on")
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.watch(pid, attempt: 0) } }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.unwatch(pid) } }
        })
        // An app that was running before access was granted, or that
        // wasn't ready at launch, is watched when it comes forward.
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid, self?.watched[pid] == nil { self?.watch(pid, attempt: 0) } }
        })
        for app in NSWorkspace.shared.runningApplications { watch(app.processIdentifier, attempt: 0) }
    }

    private func stop() {
        if !tokens.isEmpty { log.info("Quit on Close is off") }
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens = []
        watched.keys.forEach(unwatch)
    }

    /// Adds the app's observer. An app that has just launched may not
    /// answer yet, so it's tried a few more times.
    private func watch(_ pid: pid_t, attempt: Int) {
        guard watched[pid] == nil, AXIsProcessTrusted(),
              let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated,
              running.activationPolicy == .regular, pid != ProcessInfo.processInfo.processIdentifier,
              !Self.isBackground(running.bundleURL) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var observer: AXObserver?
        guard AXObserverCreate(pid, quitOnCloseChanged, &observer) == .success, let observer,
              AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon) == .success else {
            if attempt < 5 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.watch(pid, attempt: attempt + 1)
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        watched[pid] = Watched(observer: observer, app: app)
        for window in Self.read(app, kAXWindowsAttribute) as [AXUIElement]? ?? [] { opened(window, pid) }
    }

    private func unwatch(_ pid: pid_t) {
        checks.removeValue(forKey: pid)?.cancel()
        guard let app = watched.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .defaultMode)
    }

    /// Keeps a window that opened, and watches for it closing.
    private func opened(_ window: AXUIElement, _ pid: pid_t) {
        guard var app = watched[pid], Self.isUserWindow(window),
              !app.windows.contains(where: { CFEqual($0, window) }) else { return }
        AXObserverAddNotification(app.observer, window, kAXUIElementDestroyedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        app.windows.append(window)
        app.hadWindow = true
        watched[pid] = app
    }

    fileprivate func changed(_ observer: AXObserver, _ element: AXUIElement, _ notification: String) {
        guard let pid = watched.first(where: { CFEqual($0.value.observer, observer) })?.key else { return }
        if notification == kAXWindowCreatedNotification {
            opened(element, pid)
        } else if notification == kAXUIElementDestroyedNotification {
            // Long enough for an app to open the window that replaces it.
            let delay = Duration.milliseconds(settings.quitOnCloseDelayMs)
            checks[pid]?.cancel()
            checks[pid] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.check(pid)
            }
        }
    }

    /// Counts the app's windows and quits it when it has none left.
    private func check(_ pid: pid_t) {
        checks[pid] = nil
        guard var app = watched[pid], let running = NSRunningApplication(processIdentifier: pid) else { return }
        for window in Self.read(app.app, kAXWindowsAttribute) as [AXUIElement]? ?? [] { opened(window, pid) }
        app = watched[pid] ?? app
        app.windows.removeAll(where: Self.isClosed)
        watched[pid] = app
        var ids = [running.bundleIdentifier].compactMap(\.self)
        if let url = running.bundleURL {
            ids += QuitOnClose.containingApps(of: url).compactMap { Bundle(url: $0)?.bundleIdentifier }
        }
        let facts = QuitOnClose.App(bundleIds: ids, isBackground: Self.isBackground(running.bundleURL),
                                    hadWindow: app.hadWindow, windows: app.windows.count, isHidden: running.isHidden)
        let own = Bundle.main.bundleIdentifier
        if QuitOnClose.shouldQuit(facts, settings: settings, own: own) {
            log.info("Quit on Close: quitting \(running.bundleIdentifier ?? "an app", privacy: .public)")
            running.terminate()
        } else if QuitOnClose.focusesBefore(facts, settings: settings, own: own, isFrontmost: running.isActive) {
            Task { await focusBefore() }
        }
    }

    /// A window someone works in: a document or a dialog, minimized or
    /// not. Floating panels, such as an inspector, don't keep an app open.
    private static func isUserWindow(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, timeout)
        guard let role: String = read(window, kAXRoleAttribute), role == kAXWindowRole else { return false }
        let subrole: String? = read(window, kAXSubroleAttribute)
        return subrole == nil || [kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole].contains(subrole)
    }

    /// A closed window's element no longer answers. One of a busy app that
    /// doesn't answer in time still counts, so a slow app is never quit.
    private static func isClosed(_ window: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .invalidUIElement
    }

    /// A menu bar or background app, from its Info.plist.
    private static func isBackground(_ url: URL?) -> Bool {
        guard let info = url.flatMap(Bundle.init(url:))?.infoDictionary else { return false }
        return ["LSUIElement", "LSBackgroundOnly"].contains { key in
            (info[key] as? Bool) ?? (info[key] as? String).map { $0 == "1" || $0.lowercased() == "yes" || $0.lowercased() == "true" } ?? false
        }
    }

    private static func read<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}

/// The observers' callback. Their sources are on the main run loop, so it
/// runs on the main thread, and what it's given never leaves it.
private nonisolated func quitOnCloseChanged(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                            _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    nonisolated(unsafe) let observer = observer, window = element, watcher = refcon
    let name = notification as String
    MainActor.assumeIsolated {
        Unmanaged<QuitOnCloseWatcher>.fromOpaque(watcher).takeUnretainedValue().changed(observer, window, name)
    }
}
