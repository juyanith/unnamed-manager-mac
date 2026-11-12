import Foundation
import Testing
@testable import UnnamedManagerKit

private let entries = """
{ "keys": "Hyper+Space", "title": "Commands" },
{ "keys": "Hyper+Space E", "title": "Editor", "action": "edit" },
{ "keys": "Meh+Space", "title": "Snippets" },
{ "keys": "Meh+Space S", "title": "Signature", "action": "edit" },
{ "keys": "Hyper+T", "title": "Terminal", "action": "edit" },
{ "keys": "F13", "title": "Notes", "action": "edit" },
{ "keys": "T", "title": "Bare T", "action": "edit" },
{ "keys": "Meh+L", "title": "Address Bar", "action": "address" }
"""
private let actions = """
{ "edit": { "type": "application", "bundleId": "dev.zed.Zed" },
  "address": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Cmd+L" } } } }
"""

private func code(_ key: KeyName) -> UInt16 { key.keyCode! }
private func down(_ key: KeyName, _ modifiers: Modifiers = []) -> KeyEvent {
    .down(keyCode: code(key), modifiers: modifiers, isRepeat: false)
}

/// An engine in Home, having gone Back from the leader `chord`'s menu.
private func atHome(from key: KeyName = .space, _ modifiers: Modifiers = .hyper,
                    in app: String = "com.apple.Notes") throws -> SequenceEngine {
    let config = try load(json(entries: entries, actions: actions,
                               contexts: #"[{ "id": "browser", "apps": ["com.apple.Safari"] }]"#)).get()
    var e = SequenceEngine(config: config)
    e.setFrontApp(app)
    _ = e.handle(down(key, modifiers))
    guard case .showHome = e.handle(down(.backspace, modifiers)).effect else {
        Issue.record("Back didn't open Home")
        return e
    }
    return e
}

@Suite("Home (S-050)")
struct HomeTests {
    @Test("Groups are by exact modifiers, the current one first, the rest by first entry")
    func groups() throws {
        let e = try atHome(from: .space, .meh)
        let groups = try #require(e.home).groups
        #expect(groups.map(\.title) == ["Meh", "Hyper", "No modifiers"])
        #expect(groups[0].entries.map(\.title) == ["Snippets", "Address Bar"])
        #expect(groups[1].entries.map(\.title) == ["Commands", "Terminal"])
        #expect(groups[2].entries.map(\.title) == ["Notes", "Bare T"])
        #expect(e.path == ["Home"])
    }

    @Test("In the current group the key alone picks, modifiers held or not")
    func currentGroup() throws {
        for held: Modifiers in [[], .hyper, [.control, .command]] {
            var e = try atHome()
            guard case let .run(binding, _) = e.handle(down(.t, held)).effect else { Issue.record("\(held)"); continue }
            #expect(binding.title == "Terminal")
        }
    }

    @Test("Other groups need their exact chord, counting held modifiers")
    func otherGroups() throws {
        var e = try atHome()
        guard case let .showMenu(menu, path, _) = e.handle(down(.space, .meh)).effect else { Issue.record("no menu"); return }
        #expect(menu.title == "Snippets" && path == ["Home", "Snippets"])
        // Meh's own step keys work with Meh still held.
        guard case let .run(binding, _) = e.handle(down(.s, .meh)).effect else { Issue.record("no run"); return }
        #expect(binding.title == "Signature")
        // From Meh, ⌘+Space is neither Meh's key nor any entry's chord.
        var other = try atHome(from: .space, .meh)
        #expect(other.handle(down(.space, [.command])).effect == .unbound(path: ["Home"]))
        #expect(other.isActive)
    }

    @Test("A bare key picks from the current group before the group with no modifiers")
    func bareKey() throws {
        var e = try atHome()
        guard case let .run(t, _) = e.handle(down(.t)).effect else { Issue.record("no run"); return }
        #expect(t.title == "Terminal")
        var f = try atHome()
        guard case let .run(notes, _) = f.handle(down(.f13)).effect else { Issue.record("no run"); return }
        #expect(notes.title == "Notes")
    }

    @Test("A leader picked from Home goes Back to Home, with that leader's group first")
    func backToHome() throws {
        var e = try atHome()
        _ = e.handle(down(.space, .meh))
        guard case let .showHome(home, path, _) = e.handle(down(.backspace)).effect else { Issue.record("no Home"); return }
        #expect(home.current?.title == "Meh" && path == ["Home"])
    }

    @Test("Back or Cancel in Home ends the sequence")
    func leave() throws {
        var back = try atHome()
        #expect(back.handle(down(.backspace)).effect == .cancelled)
        #expect(!back.isActive)
        var cancel = try atHome()
        #expect(cancel.handle(down(.escape)).effect == .cancelled)
        #expect(!cancel.isActive)
    }

    @Test("A direct binding runs for the app that was in front when the sequence started")
    func direct() throws {
        var e = try atHome(in: "com.apple.Safari")
        e.setFrontApp("com.apple.Notes")
        guard case let .run(binding, frontApp) = e.handle(down(.l, .meh)).effect else { Issue.record("no run"); return }
        #expect(binding.title == "Address Bar" && frontApp == "com.apple.Safari")
        #expect(!e.isActive)
    }

    @Test("An unavailable direct binding flashes and stays in Home")
    func unavailable() throws {
        var e = try atHome(in: "com.apple.Notes")
        guard case let .unavailable(binding, path) = e.handle(down(.l, .meh)).effect else { Issue.record("no flash"); return }
        #expect(binding.title == "Address Bar" && path == ["Home"] && e.isActive)
    }
}
