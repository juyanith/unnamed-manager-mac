import AppKit
import SwiftUI
import OSLog
import Synchronization
import UnnamedManagerKit

/// Self-test checks for M5 and M6: the tap, Secure Input, the schema, polish.
extension SelfTest {
    /// M5: recovering the tap, Secure Event Input, the JSON Schema.
    static func systemChecks(_ model: AppModel) {
        // S-037: a "tap disabled" event turns the tap back on, passes, and is logged.
        let handled = Mutex(0)
        let context = TapContext { _ in handled.withLock { $0 += 1 }; return true }
        var passes = true
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            passes = passes && !context.handle(RawKeyEvent(type: type, keyCode: 0, isRepeat: false, flags: [], isFromLauncher: false))
        }
        check("S-037 a disabled-tap event is handled by the tap, not the engine", passes && handled.withLock { $0 } == 0)
        check("S-037 turning the tap back on is logged", logContains("turning it back on"))

        // S-038: Secure Event Input shows in the menu and badges the icon.
        let launcher = model.launcher
        launcher.setSecureInputForTesting(true)
        let secured = MenuBarStatus(launcher: launcher, store: model.store)
        check("S-038 Secure Input shows in the menu with a warning icon", secured.keyboardIsSecured && secured.icon == .warning)
        // A missing permission is the bigger problem, so it wins the label.
        check("S-038 the VoiceOver label says the keyboard is secured", secured.accessibilityLabel
              == (secured.missingPermissions.isEmpty ? "Unnamed Manager, keyboard is secured" : "Unnamed Manager, needs permission"))
        launcher.setSecureInputForTesting(false)
        check("S-038 the warning goes when Secure Input is off", !MenuBarStatus(launcher: launcher, store: model.store).keyboardIsSecured)

        // S-039: the schema is written next to the config, and the starter points at it.
        let schemaURL = model.store.url.deletingLastPathComponent().appending(path: ConfigSchema.fileName)
        check("S-039 config.schema.json is written next to the config",
              (try? Data(contentsOf: schemaURL)) == Data(ConfigSchema.json.utf8), schemaURL.path)
    }

    /// M6: the welcome window, icons, context menus, keyboard.
    static func polishChecks(_ model: AppModel) async {
        // S-040: the welcome window shows until both permissions and one sequence are done.
        check("S-040 the welcome window shows until setup is done",
              !WelcomeStatus(accessibility: true, inputMonitoring: true, ranSequence: false).isComplete
              && !WelcomeStatus(accessibility: true, inputMonitoring: false, ranSequence: true).isComplete
              && WelcomeStatus(accessibility: true, inputMonitoring: true, ranSequence: true).isComplete)

        // S-043: every right-click item is in the menu bar, with the same name.
        let contextItems = Set(OutlineCommand.forRow(isMenu: true) + OutlineCommand.forRow(isMenu: false))
        check("S-043 every context menu item is also in the menu bar", contextItems.isSubset(of: Set(OutlineCommand.inMenuBar)))
        check("S-043 Duplicate has ⌘D in the menu bar", OutlineCommand.duplicate.shortcut == KeyboardShortcut("d"))

        // S-044: VoiceOver reads each row as "key, title, action", and Return edits the title.
        let editor = model.editor
        if let binding = editor.draft.paths.compactMap({ $0 }).first(where: { editor.draft.entry($0)?.action != nil }),
           let menu = editor.draft.children(of: nil).first {
            let entry = editor.draft.entry(binding)!
            check("S-044 VoiceOver reads a binding as key, title, action",
                  editor.accessibilityLabel(for: binding) == "\(binding.lastStep!.description), \(entry.title), \(entry.action!)")
            check("S-044 VoiceOver reads a menu as key, title, menu",
                  editor.accessibilityLabel(for: menu).hasSuffix(", menu"))
            editor.select(binding, focus: .title)
            check("S-044 Return puts the cursor in the title field", editor.focus == .title && editor.recording == nil)
            editor.focus = nil
        }

        // S-052: the Help page lists your keys from the config, grouped as Home groups them.
        let help = HelpContent(config: SeedData.fixture)
        check("S-052 Help lists every leader and direct binding by group",
              help.groups.map(\.title) == ["Hyper", "Meh", "CAG"]
              && help.groups.flatMap(\.rows).map(\.title) == ["Commands", "Help", "Workspace", "Terminal"],
              help.groups.map(\.title).joined(separator: ", "))
        check("S-052 Help names the Cancel and Back keys and mentions Home",
              help.cancelKey == "esc" && help.backKey == "delete" && help.hasHome)
        check("S-052 Help has an empty state with no bindings", HelpContent(config: nil).isEmpty)
        let oneLeader = try? ConfigLoader.load(Data("""
            { "version": 1, "entries": [{ "keys": "Hyper+Space", "title": "Commands" },
              { "keys": "Hyper+Space F", "title": "Finder", "action": "f" }],
              "actions": { "f": { "type": "application", "bundleId": "com.apple.finder" } } }
            """.utf8)).get()
        check("S-052 a config with one leader has no Home on the Help page",
              oneLeader.map { HelpContent(config: $0).hasHome } == false)

        // S-081: every built-in action on the Help page, overrides marked.
        let overriding = try? ConfigLoader.load(Data("""
            { "version": 1, "entries": [{ "keys": "Hyper+F", "title": "Fill", "action": "window-fill" }],
              "actions": { "window-fill": { "type": "window.fill", "toggle": false } } }
            """.utf8)).get()
        let builtIns = HelpContent(config: overriding).builtIns
        let listed = Set(builtIns.flatMap(\.rows).map(\.name))
        check("S-081 Help lists every built-in action, kind by kind, with a row for numbered windows",
              builtIns.count == 9 && BuiltInAction.entries().allSatisfy { listed.contains($0.name) }
                  && builtIns.first { $0.title == "Focus Window" }?.rows.last?.title == "Window 1, 2, 3…",
              builtIns.map(\.title).joined(separator: ", "))
        check("S-081 Help marks a built-in action your config overrides",
              builtIns.flatMap(\.rows).filter(\.isOverridden).map(\.name) == ["window-fill"])

        // S-053: Show Help, on Hyper+H in the starter, opens the Help window.
        let starter = model.store.loaded
        check("S-053 the starter config has Show Help on Hyper+H",
              starter?.leaders.last.map { $0.path.description == "Hyper+H" && starter?.config.action(named: $0.action ?? "") == .help } == true)
        check("S-053 Show Help is a type in the Actions page's picker",
              Config.Action.types(allowsContextAware: true).contains("help"))
        // As from a chord: the window closed, through the real performer.
        window(WindowID.help)?.close()
        try? await Task.sleep(for: .seconds(0.5))
        try? await SystemPerformer().perform(.showHelp)
        try? await Task.sleep(for: .seconds(1))
        check("S-053 Show Help opens the Help window",
              window(WindowID.help)?.isVisible == true,
              NSApp.windows.map { $0.identifier?.rawValue ?? "?" }.joined(separator: ", "))
        window(WindowID.help)?.close()
    }

    /// A check that the app comes in front. NSWorkspace brings forward the
    /// app with this bundle id, so with another copy of Unnamed Manager
    /// running (your own), it brings that one and the check can't tell.
    static func frontCheck(_ name: String, _ ok: Bool, _ detail: String = "") {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count == 1 else {
            print("SKIP \(name): another copy of Unnamed Manager is running; quit it to run this check")
            return
        }
        check(name, ok, detail)
    }

    /// The window whose SwiftUI identifier starts with `prefix`.
    static func window(_ prefix: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(prefix) == true }
    }

    /// S-085: one Settings window holds your bindings and the preferences,
    /// and Settings… brings it in front, even while another app is active.
    static func frontChecks(_ model: AppModel) async {
        check("S-085 Settings has the General, Bindings, Actions, Contexts and Windows tabs",
              SettingsTab.allCases.map(\.title) == ["General", "Bindings", "Actions", "Contexts", "Windows"])
        window(WindowID.settings)?.close()
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
        try? await Task.sleep(for: .seconds(1))
        let behind = !NSApp.isActive
        model.showSettings(.windows)
        try? await Task.sleep(for: .seconds(1))
        let settings = window(WindowID.settings)
        frontCheck("S-085 Settings… brings the app and the Settings window in front of another app",
              behind && NSApp.isActive && settings?.isKeyWindow == true && model.tab == .windows,
              "behind first: \(behind), active: \(NSApp.isActive), windows: " + NSApp.windows.map { $0.identifier?.rawValue ?? "?" }.joined(separator: ", "))
        // A key on the Help page shows its binding on the Bindings tab.
        model.showHelp()
        try? await Task.sleep(for: .seconds(1))
        let helpInFront = window(WindowID.help)?.isKeyWindow == true
        model.showSettings(.bindings)
        try? await Task.sleep(for: .seconds(1))
        frontCheck("S-085 Help is a window of its own, and its links bring Settings back on the Bindings tab",
              helpInFront && settings?.isKeyWindow == true && model.tab == .bindings && window(WindowID.help)?.isVisible == true)
        let frame = settings?.frame.size ?? .zero
        check("S-085 the Bindings tab can be resized, and opens at its first size",
              settings?.styleMask.contains(.resizable) == true
                  && frame == Layout.editorTabDefault,
              "\(frame), resizable: \(settings?.styleMask.contains(.resizable) == true)")
        // As if you dragged the corner: the window keeps the size.
        if let settings {
            settings.setFrame(NSRect(origin: settings.frame.origin, size: CGSize(width: 1100, height: 760)), display: true)
            try? await Task.sleep(for: .seconds(1))
        }
        check("S-085 the Bindings tab keeps the size you give it",
              settings?.frame.size == CGSize(width: 1100, height: 760), "\(settings?.frame.size ?? .zero)")
        check("S-085 there is no separate Bindings window",
              !NSApp.windows.contains { $0.identifier?.rawValue.hasPrefix("bindings") == true })
        window(WindowID.help)?.close()
    }
}
