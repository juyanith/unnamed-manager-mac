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

        // S-053: Show Help, on Hyper+H in the starter, opens the Help page.
        let starter = model.store.loaded
        check("S-053 the starter config has Show Help on Hyper+H",
              starter?.leaders.last.map { $0.path.description == "Hyper+H" && starter?.config.actions[$0.action ?? ""] == .help } == true)
        check("S-053 Show Help is a type in the Actions page's picker",
              Config.Action.types(allowsContextAware: true).contains("help"))
        // As from a chord: the window closed, through the real performer.
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.bindings) == true }?.close()
        try? await Task.sleep(for: .seconds(0.5))
        model.sidebar = .bindings
        try? await SystemPerformer().perform(.showHelp)
        try? await Task.sleep(for: .seconds(1))
        let bindingsWindow = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.bindings) == true }
        check("S-053 Show Help opens the Bindings window on the Help page",
              model.sidebar == .help && bindingsWindow?.isVisible == true,
              NSApp.windows.map { $0.identifier?.rawValue ?? "?" }.joined(separator: ", "))
        model.sidebar = .bindings
    }
}
