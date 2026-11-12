import Foundation
import UnnamedManagerKit

/// Sample config for snapshots and the self-test. Everything in it can be
/// written in the config file today, and created in the Bindings window
/// once M4 lands.
enum SeedData {
    static let fixtureJSON = """
    {
      "version": 1,
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
        { "keys": "Hyper+Space W M", "title": "Maximize", "action": "maximize" },
        { "keys": "Hyper+Space W N", "title": "Minimize", "action": "minimize" },
        { "keys": "Hyper+Space W H", "title": "Left Half", "action": "left-half" },
        { "keys": "Hyper+Space W L", "title": "Right Half", "action": "right-half" },
        { "keys": "Hyper+Space W C", "title": "Center", "action": "move-center" },
        { "keys": "Hyper+Space W Equal", "title": "Wider", "action": "wider" },
        { "keys": "Hyper+Space W Minus", "title": "Half Size", "action": "half-size" },
        { "keys": "Hyper+Space W Right", "title": "Window to the Right", "action": "focus-right" },
        { "keys": "Hyper+Space W Tab", "title": "Next Window", "action": "focus-next" },
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
        "maximize": { "type": "window.maximize" },
        "minimize": { "type": "window.minimize" },
        "left-half": { "type": "window.place", "preset": "leftHalf" },
        "right-half": { "type": "window.place", "preset": "rightHalf" },
        "move-center": { "type": "window.move", "to": { "x": 0.5, "y": 0.5 } },
        "wider": { "type": "window.resize", "step": "grow", "widths": [0.5, 0.75, 1] },
        "half-size": { "type": "window.resize", "to": { "width": 0.5, "height": 0.5 }, "anchor": "center" },
        "focus-right": { "type": "window.focus", "direction": "right" },
        "focus-next": { "type": "window.focus", "direction": "next" },
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
