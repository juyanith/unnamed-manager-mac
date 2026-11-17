import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UnnamedManagerKit

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.json APP_SNAPSHOT=/tmp/shots build/UnnamedManager.app/Contents/MacOS/UnnamedManager
/// writes <tab>-light.png and <tab>-dark.png for every Settings tab, with
/// windows-bottom-* scrolled to its end, and help-* for the Help window, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=bindings,windows,help,hud limits the pages. "hud" is the Guide.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// The Settings window's task starts the run, and opens again if the
    /// window does, so the run must start only once.
    private static var started = false

    static func runIfRequested(model: AppModel, openWelcome: @escaping () -> Void) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty, !started else { return }
        started = true
        // Snapshots never run against the real config file.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            // The Guide's seed content may use icons the /tmp config doesn't (S-054).
            GuideIcons.shared.load(SeedData.fixture.iconSources())
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                // A row selected on each page, so the editor pane shows a form.
                model.editor.selection = KeySequence(parsing: "Hyper+Space A T")
                model.actionSelection = "find"
                model.contextSelection = "browser"
                for tab in SettingsTab.allCases where only?.contains(tab.rawValue) ?? true {
                    model.tab = tab
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(tab.rawValue)-\(mode).png")
                    if !tab.isEditor { await captureBottom(to: "\(dir)/\(tab.rawValue)-bottom-\(mode).png") }
                }
                if only?.contains("help") ?? true {
                    model.showHelp()
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/help-\(mode).png", window: SelfTest.window(WindowID.help))
                }
                if only?.contains("actions") ?? true {
                    // S-046: a Use Application action, with its Mode picker.
                    model.tab = .actions
                    model.actionSelection = "open-editor"
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/actions-app-\(mode).png")
                    // S-053: Show Help, which has no fields.
                    model.actionSelection = "show-help"
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/actions-help-\(mode).png")
                }
                if only?.contains("actions") ?? true {
                    // S-070: each window action's form.
                    model.tab = .actions
                    for id in ["left-half", "move-center", "wider", "half-size", "focus-right", "focus-next", "focus-recent", "window-fill", "arrange", "swap-2"] {
                        model.actionSelection = id
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/actions-window-\(id)-\(mode).png")
                    }
                }
                if only?.contains("help") ?? true {
                    // S-081: the Built-In Actions section, with Place Window open.
                    model.showBuiltIns("Place Window")
                    try? await Task.sleep(for: .seconds(1.2))
                    capture(to: "\(dir)/help-builtin-\(mode).png", window: SelfTest.window(WindowID.help))
                    model.openBuiltIns = []
                    SelfTest.window(WindowID.help)?.close()
                }
                if only?.contains("bindings") ?? true {
                    // S-048: a direct binding, with its editor pane.
                    model.tab = .bindings
                    model.editor.selection = KeySequence(parsing: "CAG+T")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-direct-\(mode).png")
                    // S-056: an entry with an icon of its own.
                    model.editor.selection = KeySequence(parsing: "Hyper+Space S")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-icon-\(mode).png")
                    // S-080: a binding with a built-in action, and the Built In menu.
                    model.editor.selection = KeySequence(parsing: "Hyper+Space W Left")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-builtin-\(mode).png")
                }
            }
            if only == nil || only?.contains("empty") == true {
                // S-042: each page with nothing in it.
                model.editor.preview(ConfigDocument(config: Config(entries: [])))
                model.actionSelection = nil
                model.contextSelection = nil
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases where tab.isEditor {
                        model.tab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/empty-\(tab.rawValue)-\(mode).png")
                    }
                    model.showHelp()
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/empty-help-\(mode).png", window: SelfTest.window(WindowID.help))
                    SelfTest.window(WindowID.help)?.close()
                }
                model.editor.endPreview()
            }
            if only == nil || only?.contains("bindings-error") == true {
                // S-023: a broken file shows the banner over the last valid outline.
                let good = try? Data(contentsOf: model.store.url)
                try? Data(#"{ "version": 1, "entries": [{ "keys": "Hyper+Spcae", "title": "C" }] }"#.utf8).write(to: model.store.url)
                model.store.reload()
                model.tab = .bindings
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-error-\(mode).png")
                }
                if let good { try? good.write(to: model.store.url) }
                model.store.reload()
            }
            if only == nil || only?.contains("hud") == true {
                // The Guide right after the leader, over Settings.
                let guide = model.launcher.guide
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    guide.show(SeedData.guideContent)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/hud-\(mode).png", window: guide.window)
                    // The error flash for an unbound key (S-018).
                    guide.holdFlashForSnapshot(true)
                    try? await Task.sleep(for: .seconds(0.3))
                    capture(to: "\(dir)/hud-flash-\(mode).png", window: guide.window)
                    guide.holdFlashForSnapshot(false)
                    guide.hide()
                    try? await Task.sleep(for: .seconds(0.3))
                }
            }
            if only == nil || only?.contains("hud") == true {
                // S-070: the Windows menu, with each window action's symbol.
                let guide = model.launcher.guide
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    guide.show(SeedData.windowsContent)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/hud-window-\(mode).png", window: guide.window)
                    guide.hide()
                    try? await Task.sleep(for: .seconds(0.3))
                }
            }
            if only == nil || only?.contains("hud-home") == true {
                // S-050: Home in one column, and side by side.
                let guide = model.launcher.guide
                for (name, content) in [("hud-home", SeedData.homeContent), ("hud-home-wide", SeedData.wideHomeContent)] {
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        guide.show(content)
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/\(name)-\(mode).png", window: guide.window)
                        guide.hide()
                        try? await Task.sleep(for: .seconds(0.3))
                    }
                }
            }
            if only == nil || only?.contains("menubar-icons") == true {
                // S-041: ready, off and warning on a light and a dark menu bar.
                if let png = MenuBarIcon.contactSheet() {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/menubar-icons.png"))
                    print("SNAPSHOT \(dir)/menubar-icons.png")
                }
            }
            if only == nil || only?.contains("welcome") == true {
                // S-040: the first-run window.
                let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                openWelcome()
                try? await Task.sleep(for: .seconds(1))
                let welcome = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/welcome-\(mode).png", window: welcome)
                }
                welcome?.close()
            }
            if only == nil || only?.contains("welcome-import") == true {
                // S-058: the copy offer with the old app running, then the copied state.
                for (name, state) in [("welcome-import", LauncherMigration.State.offer), ("welcome-copied", .copied)] {
                    model.migration.show(state, launcherRunning: state == .offer,
                                         source: LauncherMigration.sourceURL(environment: [:], home: URL.homeDirectory))
                    openWelcome()
                    try? await Task.sleep(for: .seconds(1))
                    // A single Window reuses its NSWindow, so find it by id, not as a new window.
                    let welcome = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.welcome) == true && $0.isVisible }
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/\(name)-\(mode).png", window: welcome)
                    }
                    welcome?.close()
                    try? await Task.sleep(for: .seconds(0.3))
                }
                model.migration.show(.hidden, launcherRunning: false)
            }
            if only == nil || only?.contains("hud-theme") == true {
                // S-020: a fixed theme wins over the Mac's mode.
                let guide = model.launcher.guide
                for (mac, theme) in [("dark", "light"), ("light", "dark")] {
                    NSApp.appearance = NSAppearance(named: mac == "light" ? .aqua : .darkAqua)
                    guide.theme = theme
                    guide.show(SeedData.guideContent)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/hud-theme-\(theme)-on-\(mac).png", window: guide.window)
                    guide.hide()
                    try? await Task.sleep(for: .seconds(0.3))
                }
                guide.theme = "system"
            }
            if only == nil || only?.contains("hud-error") == true {
                let guide = model.launcher.guide
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    guide.showFailure("Couldn't open dev.zed.Zed: not installed.", title: "Editor")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/hud-error-\(mode).png", window: guide.window)
                    guide.hide()
                    try? await Task.sleep(for: .seconds(0.3))
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    /// The settings window again, with its Form scrolled to the end, then
    /// back to the top: the sections below the fold.
    private static func captureBottom(to path: String) async {
        let settings = SelfTest.window(WindowID.settings)
        guard let scroll = settings?.contentView.flatMap(Self.scrollView), let document = scroll.documentView,
              document.bounds.height > scroll.contentView.bounds.height + 1 else { return }
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.bounds.maxY : 0))
        try? await Task.sleep(for: .seconds(0.3))
        capture(to: path, window: settings)
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? 0 : document.bounds.maxY))
    }

    /// The first scroll view in a view's tree, such as a Form's.
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap(scrollView).first
    }

    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? SelfTest.window(WindowID.settings) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
