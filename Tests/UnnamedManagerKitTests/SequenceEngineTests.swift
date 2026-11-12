import Foundation
import Testing
@testable import UnnamedManagerKit

private let entries = """
{ "keys": "Hyper+Space", "title": "Commands" },
{ "keys": "Hyper+Space E", "title": "Editor", "action": "edit" },
{ "keys": "Hyper+Space A", "title": "Applications" },
{ "keys": "Hyper+Space A T", "title": "Terminal", "action": "edit" },
{ "keys": "Hyper+Space A D", "title": "Deep" },
{ "keys": "Hyper+Space A D E", "title": "Deeper" },
{ "keys": "Hyper+Space A D E P", "title": "Deepest" },
{ "keys": "Hyper+Space A D E P X", "title": "Six", "action": "edit" },
{ "keys": "Ctrl+W", "title": "Workspace" },
{ "keys": "Ctrl+W 1", "title": "One", "action": "edit" },
{ "keys": "Hyper+T", "title": "Terminal", "action": "edit" }
"""

private func engine(runtime: String = "{}") throws -> SequenceEngine {
    SequenceEngine(config: try load(json(entries: entries, actions: minimalActions, runtime: runtime)).get())
}

private func code(_ key: KeyName) -> UInt16 { key.keyCode! }
private func down(_ key: KeyName, _ modifiers: Modifiers = [], repeat isRepeat: Bool = false) -> KeyEvent {
    .down(keyCode: code(key), modifiers: modifiers, isRepeat: isRepeat)
}

@Suite("Sequence engine (S-003, S-004, S-007)")
struct SequenceEngineTests {
    @Test("Idle: only leader chords are consumed")
    func idle() throws {
        var e = try engine()
        #expect(e.handle(down(.e)) == .pass)
        #expect(e.handle(down(.space, [.command])) == .pass)
        #expect(e.handle(.up(keyCode: code(.e))) == .pass)
        let out = e.handle(down(.space, .hyper))
        #expect(out.consume)
        guard case let .showMenu(menu, path, _) = out.effect else { Issue.record("no menu"); return }
        #expect(menu.title == "Commands" && path == ["Commands"])
        #expect(e.isActive)
    }

    @Test("A direct binding runs at once, with no sequence")
    func direct() throws {
        var e = try engine()
        e.setFrontApp("com.apple.Notes")
        let out = e.handle(down(.t, .hyper))
        guard case let .run(binding, frontApp) = out.effect else { Issue.record("no run"); return }
        #expect(out.consume && binding.title == "Terminal" && frontApp == "com.apple.Notes")
        #expect(!e.isActive)
        // Holding the chord doesn't run it again, and its key-up is consumed.
        #expect(e.handle(down(.t, .hyper, repeat: true)) == .consumed())
        #expect(e.handle(.up(keyCode: code(.t))).consume)
        // Inside a sequence the chord is just a key that isn't bound.
        _ = e.handle(down(.space, .hyper))
        guard case .unbound = e.handle(down(.t, .hyper)).effect else { Issue.record("ran inside a sequence"); return }
    }

    @Test("During a sequence every key-down, repeat and matching key-up is consumed")
    func consumesAll() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        #expect(e.handle(.up(keyCode: code(.space))).consume)
        #expect(e.handle(down(.q)).consume)
        #expect(e.handle(down(.q, repeat: true)).consume)
        #expect(e.handle(.up(keyCode: code(.q))).consume)
        #expect(e.handle(.up(keyCode: code(.z))) == .pass)
    }

    @Test("A menu key opens it, a binding key runs it and ends the sequence")
    func steps() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        guard case let .showMenu(menu, path, _) = e.handle(down(.a)).effect else { Issue.record("no menu"); return }
        #expect(menu.title == "Applications" && path == ["Commands", "Applications"])
        guard case let .run(binding, _) = e.handle(down(.t)).effect else { Issue.record("no run"); return }
        #expect(binding.title == "Terminal" && binding.action == "edit")
        #expect(!e.isActive)
        // The key-up of the binding key is still consumed after the sequence ends.
        #expect(e.handle(.up(keyCode: code(.t))).consume)
        #expect(e.handle(down(.t)) == .pass)
    }

    @Test("Held leader modifiers are ignored on steps; other modifiers don't match")
    func modifiers() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        guard case .run = e.handle(down(.e, .hyper)).effect else { Issue.record("held Hyper should be ignored"); return }

        _ = e.handle(down(.w, [.control]))
        _ = e.handle(.flags([]))
        // Ctrl was released, so Ctrl+1 now has an extra modifier.
        guard case .unbound = e.handle(down(.d1, [.control])).effect else { Issue.record("Ctrl+1 should not match"); return }
        guard case .run = e.handle(down(.d1)).effect else { Issue.record("1 should match"); return }
    }

    @Test("A step with a modifier that isn't the leader's doesn't match")
    func extraModifier() throws {
        var e = try engine()
        _ = e.handle(down(.w, [.control]))
        guard case .unbound = e.handle(down(.d1, [.control, .shift])).effect else { Issue.record("Shift should not match"); return }
        #expect(e.isActive)
    }

    @Test("An unbound key stays in the menu")
    func unbound() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        _ = e.handle(down(.a))
        guard case let .unbound(path) = e.handle(down(.z)).effect else { Issue.record("no error"); return }
        #expect(path == ["Commands", "Applications"] && e.path == ["Commands", "Applications"])
    }

    @Test("Keys match physical positions: the engine sees key codes, not characters")
    func physical() throws {
        var e = try engine()
        _ = e.handle(.down(keyCode: 0x31, modifiers: .hyper, isRepeat: false))
        // 0x0E is the E position, whatever the active layout types there.
        guard case .run = e.handle(.down(keyCode: 0x0E, modifiers: [], isRepeat: false)).effect else { Issue.record("no run"); return }
    }

    @Test("Menus nest without limit: six levels")
    func deep() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        for key: KeyName in [.a, .d, .e, .p] { _ = e.handle(down(key)) }
        #expect(e.path.count == 5)
        guard case let .run(binding, _) = e.handle(down(.x)).effect else { Issue.record("no run"); return }
        #expect(binding.path.steps.count == 5 && binding.title == "Six")
    }

    @Test("Cancel ends the sequence from any depth")
    func cancel() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        _ = e.handle(down(.a))
        _ = e.handle(down(.d))
        #expect(e.handle(down(.escape)).effect == .cancelled)
        #expect(!e.isActive)
    }

    @Test("Back goes to the parent, then Home, then ends the sequence")
    func back() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        _ = e.handle(down(.a))
        guard case let .showMenu(menu, path, _) = e.handle(down(.backspace)).effect else { Issue.record("no parent"); return }
        #expect(menu.title == "Commands" && path == ["Commands"])
        guard case let .showHome(_, homePath, _) = e.handle(down(.backspace)).effect else { Issue.record("no Home"); return }
        #expect(homePath == ["Home"] && e.isActive)
        #expect(e.handle(down(.backspace)).effect == .cancelled)
        #expect(!e.isActive)
    }

    @Test("With one top-level entry, Back from the leader's menu ends the sequence")
    func backWithoutHome() throws {
        var e = SequenceEngine(config: try load(json(entries: minimalEntries, actions: minimalActions)).get())
        _ = e.handle(down(.space, .hyper))
        #expect(e.handle(down(.backspace)).effect == .cancelled)
        #expect(!e.isActive)
    }

    @Test("Custom cancel key, and Back turned off")
    func customKeys() throws {
        var e = try engine(runtime: #"{ "cancelKey": "Q", "backKey": "" }"#)
        _ = e.handle(down(.space, .hyper))
        guard case .unbound = e.handle(down(.backspace)).effect else { Issue.record("Back should be off"); return }
        #expect(e.handle(down(.q)).effect == .cancelled)
    }

    @Test("A repeat of the held leader doesn't restart the sequence")
    func leaderRepeat() throws {
        var e = try engine()
        _ = e.handle(down(.space, .hyper))
        _ = e.handle(down(.a))
        #expect(e.handle(down(.space, .hyper, repeat: true)).consume)
        #expect(e.path == ["Commands", "Applications"])
    }

    @Test("A thousand events take well under a millisecond each")
    func speed() throws {
        var e = try engine()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0..<1_000 {
                _ = e.handle(i % 3 == 0 ? down(.space, .hyper) : down(.a))
                _ = e.handle(.up(keyCode: code(.a)))
            }
        }
        #expect(elapsed < .milliseconds(200))
    }
}
