import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UnnamedManagerKit

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.json APP_SNAPSHOT=/tmp/shots build/UnnamedManager.app/Contents/MacOS/UnnamedManager
/// writes <page>-light.png and <page>-dark.png for every Bindings page, and
/// settings-light.png and settings-dark.png for Settings, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=bindings,settings,hud limits the pages. "hud" is the Guide.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWelcome: @escaping () -> Void) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
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
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
                if only?.contains("actions") ?? true {
                    // S-046: a Use Application action, with its Mode picker.
                    model.sidebar = .actions
                    model.actionSelection = "open-editor"
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/actions-app-\(mode).png")
                    // S-053: Show Help, which has no fields.
                    model.actionSelection = "show-help"
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/actions-help-\(mode).png")
                }
                if only?.contains("bindings") ?? true {
                    // S-048: a direct binding, with its editor pane.
                    model.sidebar = .bindings
                    model.editor.selection = KeySequence(parsing: "CAG+T")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-direct-\(mode).png")
                    // S-056: an entry with an icon of its own.
                    model.editor.selection = KeySequence(parsing: "Hyper+Space S")
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-icon-\(mode).png")
                }
            }
            if only == nil || only?.contains("empty") == true {
                // S-042: each page with nothing in it.
                model.editor.preview(ConfigDocument(config: Config(entries: [])))
                model.actionSelection = nil
                model.contextSelection = nil
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for page in SidebarItem.allCases {
                        model.sidebar = page
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/empty-\(page.rawValue)-\(mode).png")
                    }
                }
                model.editor.endPreview()
            }
            if only == nil || only?.contains("bindings-error") == true {
                // S-023: a broken file shows the banner over the last valid outline.
                let good = try? Data(contentsOf: model.store.url)
                try? Data(#"{ "version": 1, "entries": [{ "keys": "Hyper+Spcae", "title": "C" }] }"#.utf8).write(to: model.store.url)
                model.store.reload()
                model.sidebar = .bindings
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/bindings-error-\(mode).png")
                }
                if let good { try? good.write(to: model.store.url) }
                model.store.reload()
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.canBecomeKey }
                    capture(to: "\(dir)/settings-\(mode).png", window: settings)
                }
            }
            if only == nil || only?.contains("hud") == true {
                // The Guide right after the leader, over the Bindings window.
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
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
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
