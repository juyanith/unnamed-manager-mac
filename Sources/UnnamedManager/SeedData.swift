import Foundation
import UnnamedManagerKit

/// Sample config for snapshots and the self-test. Everything in it can be
/// written in the config file today, and created in Settings
/// once M4 lands.
enum SeedData {
    static let fixtureJSON = """
    {
      "version": 1,
      "windows": { "quitOnClose": true, "displays": { "3840x1080": { "steps": { "across": 48, "down": 12 } } }, "apps": { "com.apple.calculator": { "arrange": false, "quit": false }, "com.apple.finder": { "focus": false, "swap": false }, "com.apple.Safari": { "minWidth": 1000 } } },
      "entries": [
        { "keys": "Hyper+Space", "title": "Commands" },
        { "keys": "Hyper+Space Space", "title": "Spotlight", "action": "spotlight" },
        { "keys": "Hyper+Space E", "title": "Editor", "action": "open-editor" },
        { "keys": "Hyper+Space B", "title": "Browser", "action": "open-browser" },
        { "keys": "Hyper+Space A", "title": "Applications" },
        { "keys": "Hyper+Space A T", "title": "Terminal", "action": "open-terminal" },
        { "keys": "Hyper+Space A M", "title": "Messages", "action": "open-messages" },
        { "keys": "Hyper+Space N", "title": "Notes for the weekly planning meeting", "action": "notes" },
        { "keys": "Hyper+Space S", "title": "Screenshot", "action": "screenshot", "icon": "camera" },
        { "keys": "Hyper+Space L", "title": "Address Bar", "action": "address-bar" },
        { "keys": "Hyper+Space F", "title": "Find", "action": "find" },
        { "keys": "Hyper+Space W", "title": "Windows" },
        { "keys": "Hyper+Space W F", "title": "Fill", "action": "window-fill" },
        { "keys": "Hyper+Space W N", "title": "Minimize", "action": "minimize" },
        { "keys": "Hyper+Space W H", "title": "Left Half", "action": "left-half" },
        { "keys": "Hyper+Space W L", "title": "Right Half", "action": "right-half" },
        { "keys": "Hyper+Space W C", "title": "Center", "action": "move-center" },
        { "keys": "Hyper+Space W Equal", "title": "Wider", "action": "wider" },
        { "keys": "Hyper+Space W Minus", "title": "Half Size", "action": "half-size" },
        { "keys": "Hyper+Space W A", "title": "Arrange Three", "action": "arrange" },
        { "keys": "Hyper+Space W T", "title": "Tidy Windows", "action": "window-tidy" },
        { "keys": "Hyper+Space W U", "title": "Undo Layout", "action": "window-undo" },
        { "keys": "Hyper+Space W Right", "title": "Window to the Right", "action": "focus-right" },
        { "keys": "Hyper+Space W Tab", "title": "Next Window", "action": "focus-next" },
        { "keys": "Hyper+Space W B", "title": "Window Used Before", "action": "focus-recent" },
        { "keys": "Hyper+Space W Left", "title": "Swap Left", "action": "window-swap-left" },
        { "keys": "Hyper+Space W 2", "title": "Swap With Window 2", "action": "swap-2" },
        { "keys": "Hyper+Space W S", "title": "Space Left", "action": "space-switch-left" },
        { "keys": "Hyper+Space W D", "title": "Space Right", "action": "space-right" },
        { "keys": "Hyper+Space W 1", "title": "Space 1", "action": "space-1" },
        { "keys": "Hyper+Space W 3", "title": "Send to Space 3", "action": "send-3" },
        { "keys": "Hyper+Space W G", "title": "Follow to Space 2", "action": "follow-2" },
        { "keys": "Meh+W", "title": "Workspace" },
        { "keys": "Meh+W 1", "title": "Workspace 1", "action": "workspace-1" },
        { "keys": "CAG+T", "title": "Terminal", "action": "open-terminal" },
        { "keys": "Hyper+H", "title": "Help", "action": "show-help" }
      ],
      "actions": {
        "spotlight": { "type": "send", "keys": "Cmd+Space" },
        "open-editor": { "type": "application", "bundleId": "dev.zed.Zed" },
        "open-browser": { "type": "application", "bundleId": "com.apple.Safari" },
        "open-terminal": { "type": "application", "bundleId": "com.apple.Terminal" },
        "open-messages": { "type": "application", "bundleId": "com.apple.MobileSMS" },
        "notes": { "type": "open", "target": "~/Documents" },
        "screenshot": { "type": "send", "keys": "Cmd+Shift+4" },
        "workspace-1": { "type": "send", "keys": "Ctrl+1" },
        "show-help": { "type": "help" },
        "window-fill": { "type": "window.fill", "toggle": false },
        "arrange": { "type": "window.arrange", "count": 3 },
        "minimize": { "type": "window.minimize" },
        "left-half": { "type": "window.place", "preset": "leftHalf" },
        "right-half": { "type": "window.place", "preset": "rightHalf" },
        "move-center": { "type": "window.move", "to": { "x": 0.5, "y": 0.5 } },
        "wider": { "type": "window.resize", "step": "grow", "widths": [0.5, 0.75, 1] },
        "half-size": { "type": "window.resize", "to": { "width": 0.5, "height": 0.5 }, "anchor": "center" },
        "focus-right": { "type": "window.focus", "target": "right" },
        "focus-next": { "type": "window.focus", "target": "next", "scope": "display" },
        "focus-recent": { "type": "window.focus", "target": "recent" },
        "swap-2": { "type": "window.swap", "target": 2, "scope": "display" },
        "space-right": { "type": "space.switch", "target": "right" },
        "space-1": { "type": "space.switch", "target": 1 },
        "send-3": { "type": "space.send", "target": 3 },
        "follow-2": { "type": "space.follow", "target": 2 },
        "address-bar": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Cmd+L" } } },
        "find": {
          "type": "contextual",
          "variants": { "browser": { "type": "send", "keys": "Cmd+F" } },
          "fallback": { "type": "send", "keys": "Cmd+F" }
        }
      },
      "contexts": [
        { "id": "browser", "apps": ["com.apple.Safari", "com.google.Chrome"] }
      ]
    }
    """

    static var fixture: LoadedConfig {
        // The fixture is part of the app, so a failure here is a bug in it.
        try! ConfigLoader.load(Data(fixtureJSON.utf8)).get()
    }

    /// The Guide as it looks right after pressing the leader.
    static var guideContent: GuideContent {
        let config = fixture
        let leader = config.leaders[0]
        // In Notes, so the browser-only Address Bar shows as unavailable.
        return GuideContent(menu: leader, path: [leader.title], config: config,
                            frontApp: "com.apple.Notes", frontAppName: "Notes")
    }

    /// The leader as a held menu, with the highlight on its second item (S-091).
    static var heldContent: GuideContent {
        let config = fixture
        let leader = config.leaders[0]
        return GuideContent(menu: leader, path: [leader.title], config: config,
                            frontApp: "com.apple.Notes", frontAppName: "Notes", highlight: 2)
    }

    /// Recent Windows, held, with a window of each kind the Guide marks (S-092).
    static var recentContent: GuideContent {
        let json = #"{ "version": 1, "entries": [{ "keys": "CAG+H", "title": "Recent Windows", "hold": true, "list": { "type": "windows.recent" } }] }"#
        let config = try! ConfigLoader.load(Data(json.utf8)).get()
        let items = [
            ListItem(id: 1, title: "Apple", app: "com.apple.Safari"),
            ListItem(id: 2, title: "Weekly planning", app: "com.apple.Notes", marks: .otherSpace),
            ListItem(id: 3, title: "Terminal", app: "com.apple.Terminal", marks: .hidden),
            ListItem(id: 4, title: "Draft of the quarterly report for the team", app: "com.apple.TextEdit", marks: .minimized),
            ListItem(id: 5, title: "Inbox", app: "com.apple.mail", marks: [.otherSpace, .otherDisplay]),
        ]
        let list = config.leaders[0].filled(with: items, front: ListItem(id: 0, title: "UnnamedManager — Zed", app: "dev.zed.Zed"))
        GuideIcons.shared.load(Set(([list.front!] + items).compactMap { $0.app.map(IconSource.app) }))
        return GuideContent(menu: list, path: [list.title], config: config, frontApp: nil, highlight: 1)
    }

    /// Recent Windows with 20 windows, on its second page of three, with More (S-093).
    static var recentMoreContent: GuideContent {
        let json = #"{ "version": 1, "entries": [{ "keys": "CAG+H", "title": "Recent Windows", "hold": true, "list": { "type": "windows.recent", "count": 20 } }] }"#
        let config = try! ConfigLoader.load(Data(json.utf8)).get()
        let apps = ["com.apple.Safari", "com.apple.Notes", "com.apple.Terminal", "com.apple.TextEdit", "com.apple.mail"]
        let items = (1...20).map { ListItem(id: $0, title: "Window \($0)", app: apps[$0 % apps.count]) }
        let list = config.leaders[0].filled(with: items, front: ListItem(id: 0, title: "UnnamedManager — Zed", app: "dev.zed.Zed")).onPage(1)
        GuideIcons.shared.load(Set(([list.front!] + items).compactMap { $0.app.map(IconSource.app) }))
        return GuideContent(menu: list, path: list.pathTitles, config: config, frontApp: nil, highlight: 1)
    }

    /// The Windows menu under Commands (S-070).
    static var windowsContent: GuideContent {
        let config = fixture
        let leader = config.leaders[0]
        let windows = leader.children.first { $0.title == "Windows" }!
        return GuideContent(menu: windows, path: [leader.title, windows.title], config: config,
                            frontApp: "com.apple.Notes", frontAppName: "Notes")
    }

    /// Home after Back from Commands, in Notes (S-050).
    static var homeContent: GuideContent {
        let config = fixture
        let home = Home(leaders: config.leaders, current: .hyper)
        return GuideContent(home: home, path: [Home.title], config: config,
                            frontApp: "com.apple.Notes", frontAppName: "Notes")
    }

    /// Home with more rows than one column holds, so its groups sit side by side.
    static var wideHomeContent: GuideContent {
        let direct: [(String, String)] = [
            ("Hyper+T", "Terminal"), ("Hyper+B", "Browser"), ("Hyper+M", "Mail"), ("Hyper+N", "Notes"),
            ("Hyper+C", "Calendar"), ("Hyper+F", "Finder"), ("Hyper+L", "Address Bar"),
            ("Meh+S", "Screenshot"), ("Meh+R", "Record Screen"), ("Meh+P", "Passwords"),
            ("CAG+T", "New Terminal Window"), ("CAG+M", "Music"),
            ("Cmd+F13", "Dictation"),
        ]
        let entries = [#"{ "keys": "Hyper+Space", "title": "Commands" }"#, #"{ "keys": "Hyper+Space E", "title": "Editor", "action": "n" }"#,
                       #"{ "keys": "Meh+W", "title": "Workspace" }"#, #"{ "keys": "Meh+W 1", "title": "Workspace 1", "action": "n" }"#]
            + direct.map { #"{ "keys": "\#($0.0)", "title": "\#($0.1)", "action": "\#($0.0 == "Hyper+L" ? "address" : "n")" }"# }
        let json = """
        { "version": 1, "entries": [\(entries.joined(separator: ","))],
          "actions": { "n": { "type": "noop" },
                       "address": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Cmd+L" } } } },
          "contexts": [{ "id": "browser", "apps": ["com.apple.Safari"] }] }
        """
        let config = try! ConfigLoader.load(Data(json.utf8)).get()
        return GuideContent(home: Home(leaders: config.leaders, current: .hyper), path: [Home.title], config: config,
                            frontApp: "com.apple.Notes", frontAppName: "Notes")
    }
}
