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
            for page in pages(openWelcome: openWelcome) where only?.contains(page.selector) ?? true {
                await page.before(model)
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    let window = await page.show(model, mode)
                    try? await Task.sleep(for: .seconds(page.wait))
                    capture(to: "\(dir)/\(page.file(mode)).png", window: window)
                    if page.bottom { await captureBottom(to: "\(dir)/\(page.name)-bottom-\(mode).png") }
                    await page.hide(model)
                }
                await page.after(model)
            }
            if only == nil || only?.contains("menubar-icons") == true {
                // S-041: ready, off and warning on a light and a dark menu bar, in one PNG.
                if let png = MenuBarIcon.contactSheet() {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/menubar-icons.png"))
                    print("SNAPSHOT \(dir)/menubar-icons.png")
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// One snapshot page: shown, captured in light and dark, then hidden.
    /// `APP_SNAPSHOT_PAGES` picks pages by `selector`, which several pages
    /// can share, as every Actions page shares "actions".
    private struct Page {
        let selector: String
        /// The file name before -light.png or -dark.png.
        let name: String
        var wait = 0.8
        /// Also captures `<name>-bottom-<mode>.png`, the Form scrolled to its end.
        var bottom = false
        /// Once before both modes, and once after.
        var before: (AppModel) async -> Void = { _ in }
        var after: (AppModel) async -> Void = { _ in }
        /// Shows the page for a mode and returns its window; nil is Settings.
        var show: (AppModel, String) async -> NSWindow?
        var hide: (AppModel) async -> Void = { _ in }
        /// The file name for a mode.
        var fileName: ((String) -> String)?

        func file(_ mode: String) -> String { fileName?(mode) ?? "\(name)-\(mode)" }
    }

    private static var help: NSWindow? { SelfTest.window(WindowID.help) }
    /// A single Window reuses its NSWindow, so it's found by id, not as a new window (S-058).
    private static var welcome: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.welcome) == true && $0.isVisible }
    }

    /// A Settings page: a tab with a row selected.
    private static func settings(_ selector: String, _ name: String, tab: SettingsTab, bottom: Bool = false,
                                 select: @escaping (AppModel) -> Void = { _ in }) -> Page {
        Page(selector: selector, name: name, bottom: bottom) { model, _ in
            model.tab = tab
            select(model)
            return nil
        }
    }

    /// A Guide page, hidden after each capture.
    private static func guide(_ selector: String, _ name: String, _ content: GuideContent) -> Page {
        Page(selector: selector, name: name, show: { model, _ in
            model.launcher.guide.show(content)
            return model.launcher.guide.window
        }, hide: hideGuide)
    }

    private static func hideGuide(_ model: AppModel) async {
        model.launcher.guide.hide()
        try? await Task.sleep(for: .seconds(0.3))
    }

    /// Every page, in the order they're taken.
    private static func pages(openWelcome: @escaping () -> Void) -> [Page] {
        // A row selected on each tab, so the editor pane shows a form.
        let tabs = SettingsTab.allCases.map { tab in
            settings(tab.rawValue, tab.rawValue, tab: tab, bottom: !tab.isEditor) { model in
                model.editor.selection = KeySequence(parsing: "Hyper+Space A T")
                model.actionSelection = "find"
                model.contextSelection = "browser"
            }
        }
        let action = { (name: String, id: String) in settings("actions", name, tab: .actions) { $0.actionSelection = id } }
        let binding = { (name: String, keys: String) in
            settings("bindings", name, tab: .bindings) { $0.editor.selection = KeySequence(parsing: keys) }
        }
        let held = HeldPreview()
        let heldPage = { (name: String, path: KeySequence) in
            Page(selector: name, name: name, before: { $0.editor.preview(held.document) },
                 after: { $0.editor.endPreview() }) { model, _ in
                model.tab = .bindings
                model.editor.selection = path
                return nil
            }
        }
        let empty = { (tab: SettingsTab) in
            Page(selector: "empty", name: "empty-\(tab.rawValue)", before: Self.emptyPreview, after: { $0.editor.endPreview() }) { model, _ in
                model.tab = tab
                return nil
            }
        }
        let welcomePage = { (selector: String, name: String, state: LauncherMigration.State?) in
            Page(selector: selector, name: name, before: { model in
                if let state {
                    model.migration.show(state, launcherRunning: state == .offer,
                                         source: LauncherMigration.sourceURL(environment: [:], home: URL.homeDirectory))
                }
                openWelcome()
                try? await Task.sleep(for: .seconds(1))
            }, after: { model in
                welcome?.close()
                try? await Task.sleep(for: .seconds(0.3))
                if state == .copied { model.migration.show(.hidden, launcherRunning: false) }
            }) { _, _ in welcome }
        }
        var brokenFile: Data?
        return tabs + [
            Page(selector: "help", name: "help", wait: 1) { model, _ in
                model.showHelp()
                return help
            },
            // S-046: a Use Application action, with its Mode picker. S-053: Show Help, which has no fields.
            action("actions-app", "open-editor"),
            action("actions-help", "show-help"),
        ] + [
            // S-070: each window action's form.
            "left-half", "move-center", "wider", "half-size", "focus-right", "focus-next", "focus-recent",
            "window-fill", "arrange", "swap-2", "space-right", "send-3",
        ].map { action("actions-window-\($0)", $0) } + [
            // S-081: the Built-In Actions section, with Place Window open.
            Page(selector: "help", name: "help-builtin", wait: 1.2, show: { model, _ in
                model.showBuiltIns("Place Window")
                return help
            }, hide: { $0.openBuiltIns = [] }),
            // S-094: the Held Menus section.
            Page(selector: "help", name: "help-held", wait: 1.2, after: { _ in help?.close() }) { model, _ in
                model.revealBuiltIn = HelpContent.heldMenusID
                model.showHelp()
                return help
            },
            // S-048: a direct binding. S-056: an entry with an icon of its own. S-080: a built-in action.
            binding("bindings-direct", "CAG+T"),
            binding("bindings-icon", "Hyper+Space S"),
            binding("bindings-builtin", "Hyper+Space W Left"),
            // S-094: Hold to Choose on a leader, and a menu that's Recent Windows. S-095: a list that swaps.
            heldPage("bindings-hold", held.leader),
            heldPage("bindings-list", held.recent),
            heldPage("bindings-swap", held.swap),
        ] + SettingsTab.allCases.filter(\.isEditor).map(empty) + [
            // S-042: Help with nothing in it.
            Page(selector: "empty", name: "empty-help", wait: 1, before: Self.emptyPreview, after: { $0.editor.endPreview() },
                 show: { model, _ in
                     model.showHelp()
                     return help
                 }, hide: { _ in help?.close() }),
            // S-023: a broken file shows the banner over the last valid outline.
            Page(selector: "bindings-error", name: "bindings-error", before: { model in
                brokenFile = try? Data(contentsOf: model.store.url)
                try? Data(#"{ "version": 1, "entries": [{ "keys": "Hyper+Spcae", "title": "C" }] }"#.utf8).write(to: model.store.url)
                model.store.reload()
            }, after: { model in
                if let brokenFile { try? brokenFile.write(to: model.store.url) }
                model.store.reload()
            }) { model, _ in
                model.tab = .bindings
                return nil
            },
            // The Guide right after the leader, over Settings.
            guide("hud", "hud", SeedData.guideContent),
            // S-018: the error flash for an unbound key.
            Page(selector: "hud", name: "hud-flash", wait: 1.1, show: { model, _ in
                model.launcher.guide.show(SeedData.guideContent)
                model.launcher.guide.holdFlashForSnapshot(true)
                return model.launcher.guide.window
            }, hide: { model in
                model.launcher.guide.holdFlashForSnapshot(false)
                await hideGuide(model)
            }),
            // S-091: a held menu, with Cancel and the highlight. S-092: Recent Windows. S-093: its second page.
            guide("hud-held", "hud-held", SeedData.heldContent),
            guide("hud-recent", "hud-recent", SeedData.recentContent),
            guide("hud-recent-more", "hud-recent-more", SeedData.recentMoreContent),
            // S-070: the Windows menu, with each window action's symbol.
            guide("hud", "hud-window", SeedData.windowsContent),
            // S-050: Home in one column, and side by side.
            guide("hud-home", "hud-home", SeedData.homeContent),
            guide("hud-home", "hud-home-wide", SeedData.wideHomeContent),
            // S-040: the first-run window. S-058: the copy offer with the old app running, then the copied state.
            welcomePage("welcome", "welcome", nil),
            welcomePage("welcome-import", "welcome-import", .offer),
            welcomePage("welcome-import", "welcome-copied", .copied),
            // S-020: a fixed theme wins over the Mac's mode: light on a dark Mac, dark on a light one.
            Page(selector: "hud-theme", name: "hud-theme", after: { $0.launcher.guide.theme = "system" }, show: { model, mac in
                model.launcher.guide.theme = mac == "light" ? "dark" : "light"
                model.launcher.guide.show(SeedData.guideContent)
                return model.launcher.guide.window
            }, hide: hideGuide, fileName: { mac in "hud-theme-\(mac == "light" ? "dark" : "light")-on-\(mac)" }),
            Page(selector: "hud-error", name: "hud-error", show: { model, _ in
                model.launcher.guide.showFailure("Couldn't open dev.zed.Zed: not installed.", title: "Editor")
                return model.launcher.guide.window
            }, hide: hideGuide),
        ]
    }

    private static func emptyPreview(_ model: AppModel) async {
        model.editor.preview(ConfigDocument(config: Config(entries: [])))
        model.actionSelection = nil
        model.contextSelection = nil
    }

    /// S-094 and S-095: the sample config with Hold on its leader, a Recent
    /// Windows list, and a list that swaps.
    private struct HeldPreview {
        let leader = KeySequence(parsing: "Hyper+Space")!
        let recent = KeySequence(parsing: "Hyper+Space R")!
        let swap = KeySequence(parsing: "Hyper+Space O")!

        var document: ConfigDocument {
            var document = ConfigDocument(config: SeedData.fixture.config)
            document.setHold(leader, true)
            let at = document.config.entries.firstIndex { $0.keys == "Hyper+Space N" }!
            document.config.entries.insert(Config.Entry(keys: recent.description, title: "Recent Windows",
                                                        list: Config.List(count: 20, minimized: false, spaces: "current")), at: at)
            document.config.entries.insert(Config.Entry(keys: swap.description, title: "Swap With",
                                                        list: Config.List(choose: "swap")), at: at)
            return document
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
        // Back to exactly where it was, since the dark capture of the same tab comes next.
        let top = scroll.contentView.bounds.origin
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.bounds.maxY : 0))
        try? await Task.sleep(for: .seconds(0.3))
        capture(to: path, window: settings)
        scroll.contentView.scroll(to: top)
        scroll.reflectScrolledClipView(scroll.contentView)
        try? await Task.sleep(for: .seconds(0.3))
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
