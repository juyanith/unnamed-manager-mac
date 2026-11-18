import Foundation
import Testing
@testable import UnnamedManagerKit

private let cag: Modifiers = [.control, .option, .command]

private let entries = """
{ "keys": "CAG+A", "title": "Apps", "hold": true },
{ "keys": "CAG+A T", "title": "Terminal", "action": "edit" },
{ "keys": "CAG+A B", "title": "Browser", "action": "edit" },
{ "keys": "CAG+A W", "title": "Windows" },
{ "keys": "CAG+A W F", "title": "Fill", "action": "window-fill" },
{ "keys": "CAG+A W M", "title": "Minimize", "action": "window-minimize" },
{ "keys": "CAG+A E", "title": "Search", "action": "search" },
{ "keys": "Hyper+U", "title": "Up Menu", "hold": true },
{ "keys": "Hyper+U Up", "title": "On Up", "action": "edit" },
{ "keys": "Hyper+U X", "title": "Other", "action": "edit" },
{ "keys": "CAG+D", "title": "Window" },
{ "keys": "CAG+D D", "title": "Center", "action": "window-place-center" },
{ "keys": "CAG+D S", "title": "Left Half", "action": "window-place-left-half" }
"""

/// Search runs only in a browser, so Zed in front makes it unavailable.
private let actions = """
{ "edit": { "type": "application", "bundleId": "dev.zed.Zed" },
  "search": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Primary+L" } } } }
"""

private func engine(runtime: String = "{}") throws -> SequenceEngine {
    let text = json(entries: entries, actions: actions,
                    contexts: #"[{ "id": "browser", "apps": ["com.google.Chrome"] }]"#, runtime: runtime)
    var engine = SequenceEngine(config: try load(text).get())
    engine.setFrontApp("dev.zed.Zed")
    return engine
}

private func down(_ key: KeyName, _ modifiers: Modifiers = cag, repeat isRepeat: Bool = false) -> KeyEvent {
    .down(keyCode: key.keyCode!, modifiers: modifiers, isRepeat: isRepeat)
}

/// The highlight a held effect shows, with its menu's title.
private func held(_ output: SequenceOutput) -> (String, Int)? {
    guard case let .showHeld(menu, highlight, _, _) = output.effect else { return nil }
    return (menu.title, highlight)
}

private func ran(_ effect: SequenceEffect?) -> String? {
    guard case let .run(binding, _) = effect else { return nil }
    return binding.title
}

@Suite("Held menus (S-090, spec v18)")
struct HeldMenuTests {
    @Test("Opening a held menu highlights its first item after Cancel")
    func opens() throws {
        var e = try engine()
        let output = e.handle(down(.a))
        #expect(output.consume)
        #expect(held(output)! == ("Apps", 1))
        #expect(e.isHeld)
    }

    @Test("A quick press and release runs the first item, with no other key")
    func tap() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        let output = e.handle(.flags([]))
        // Modifier changes always reach the app in front.
        #expect(!output.consume)
        #expect(ran(output.effect) == "Terminal")
        #expect(!e.isActive && !e.isHeld)
    }

    @Test("The repeat key moves on, and wraps through Cancel")
    func repeatKey() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(held(e.handle(down(.a)))! == ("Apps", 2))
        #expect(held(e.handle(down(.a)))! == ("Apps", 3))
        #expect(held(e.handle(down(.a)))! == ("Apps", 4))
        #expect(held(e.handle(down(.a)))! == ("Apps", 0))
        #expect(held(e.handle(down(.a)))! == ("Apps", 1))
        _ = e.handle(down(.a))
        #expect(ran(e.handle(.flags([])).effect) == "Browser")
    }

    @Test("Shift with the repeat key moves back")
    func shiftBack() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(held(e.handle(down(.a, cag.union(.shift))))! == ("Apps", 0))
        #expect(held(e.handle(down(.a, cag.union(.shift))))! == ("Apps", 4))
    }

    @Test("With Shift in the leader, Shift doesn't reverse: the repeat key moves on")
    func shiftLeader() throws {
        var e = try engine()
        _ = e.handle(down(.u, .hyper))
        #expect(held(e.handle(down(.u, .hyper)))! == ("Up Menu", 2))
    }

    @Test("Down and Up move the highlight, unless an item has that key")
    func arrows() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(held(e.handle(down(.down)))! == ("Apps", 2))
        #expect(held(e.handle(down(.up)))! == ("Apps", 1))
        #expect(held(e.handle(down(.up)))! == ("Apps", 0))

        var u = try engine()
        _ = u.handle(down(.u, .hyper))
        // Up is an item here, so it highlights that item.
        #expect(held(u.handle(down(.up, .hyper)))! == ("Up Menu", 1))
        #expect(held(u.handle(down(.down, .hyper)))! == ("Up Menu", 2))
    }

    @Test("A key repeat moves the highlight once")
    func repeats() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.a))
        #expect(e.handle(down(.a, repeat: true)).effect == nil)
        #expect(e.handle(down(.a, repeat: true)).effect == nil)
        #expect(e.highlight == 2)
    }

    @Test("A binding's key moves the highlight there, and runs only on letting go")
    func bindingKey() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(held(e.handle(down(.b)))! == ("Apps", 2))
        #expect(e.isActive)
        #expect(ran(e.handle(.flags([])).effect) == "Browser")
    }

    @Test("A menu's key opens it held, with its key as the repeat key")
    func menuKey() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(held(e.handle(down(.w)))! == ("Windows", 1))
        #expect(held(e.handle(down(.w)))! == ("Windows", 2))
        #expect(ran(e.handle(.flags([])).effect) == "Minimize")
    }

    @Test("Letting go chooses for every order the three modifiers come up in", arguments: [
        [Modifiers.control, .option, .command], [.control, .command, .option], [.option, .control, .command],
        [.option, .command, .control], [.command, .control, .option], [.command, .option, .control],
    ])
    func releaseOrder(_ order: [Modifiers]) throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.b))
        var held = cag
        var chosen: [String] = []
        for modifier in order {
            held.remove(modifier)
            if let title = ran(e.handle(.flags(held)).effect) { chosen.append(title) }
        }
        #expect(chosen == ["Browser"])
    }

    @Test("Pressing another modifier doesn't choose")
    func extraModifier() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        #expect(e.handle(.flags(cag.union(.shift))).effect == nil)
        #expect(e.isHeld)
    }

    @Test("Letting go on a menu goes on as an ordinary menu, with no modifiers held")
    func chooseMenu() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.a))
        _ = e.handle(down(.a))
        guard case let .showMenu(menu, path, _) = e.handle(.flags([])).effect else { Issue.record("no menu"); return }
        #expect(menu.title == "Windows" && path == ["Apps", "Windows"])
        #expect(!e.isHeld && e.isActive)
        // Ordinary now: a key runs at once.
        #expect(ran(e.handle(down(.f, [])).effect) == "Fill")
    }

    @Test("Letting go on Cancel ends the sequence and runs nothing")
    func chooseCancel() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.up))
        #expect(e.handle(.flags([])).effect == .cancelled)
        #expect(!e.isActive)
    }

    @Test("Letting go on an unavailable binding stays in its menu, now ordinary")
    func unavailable() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.e))
        guard case .unavailable = e.handle(.flags([])).effect else { Issue.record("not unavailable"); return }
        #expect(e.isActive && !e.isHeld)
        #expect(ran(e.handle(down(.t, [])).effect) == "Terminal")
    }

    @Test("Cancel ends at once, and Back goes up with the highlight on the menu you came from")
    func cancelAndBack() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.w))
        #expect(held(e.handle(down(.backspace)))! == ("Apps", 3))
        #expect(e.handle(down(.escape)).effect == .cancelled)
        #expect(!e.isActive)
    }

    @Test("Back from a held leader's menu opens Home, which isn't held")
    func home() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        guard case .showHome = e.handle(down(.backspace)).effect else { Issue.record("no Home"); return }
        #expect(!e.isHeld)
        #expect(e.handle(.flags([])).effect == nil)
        #expect(e.home != nil)
    }

    @Test("An unbound key stays where it is, highlight and all")
    func unbound() throws {
        var e = try engine()
        _ = e.handle(down(.a))
        _ = e.handle(down(.b))
        guard case .unbound = e.handle(down(.z)).effect else { Issue.record("not unbound"); return }
        #expect(e.highlight == 2)
    }

    @Test("A leader without Hold works as before: press, let go, then a key")
    func ordinary() throws {
        var e = try engine()
        guard case .showMenu = e.handle(down(.d)).effect else { Issue.record("no menu"); return }
        #expect(e.handle(.flags([])).effect == nil)
        #expect(ran(e.handle(down(.s, [])).effect) == "Left Half")
    }

    @Test("No timeout while held; the timeout starts once a chosen menu goes on")
    func timeout() throws {
        var e = try engine()
        var schedule = GuideSchedule(runtime: { var r = Config.Runtime(); r.timeoutMs = 1_000; return r }(), ui: .init())
        _ = schedule.handle(e.handle(down(.a)).effect!, at: 0)
        #expect(schedule.isVisible)
        #expect(schedule.nextDeadline == nil)
        _ = e.handle(down(.a))
        _ = schedule.handle(e.handle(down(.a)).effect!, at: 10)
        #expect(schedule.nextDeadline == nil)
        _ = schedule.handle(e.handle(.flags([])).effect!, at: 20)
        #expect(schedule.nextDeadline == 1_020)
    }

    @Test("Letting go before the Guide's delay chooses with no Guide")
    func beforeGuide() throws {
        var e = try engine()
        var schedule = GuideSchedule(runtime: { var r = Config.Runtime(); r.hudDelayMs = 400; return r }(), ui: .init())
        #expect(schedule.handle(e.handle(down(.a)).effect!, at: 0).isEmpty)
        #expect(schedule.handle(e.handle(down(.b)).effect!, at: 50).isEmpty)
        #expect(schedule.handle(e.handle(.flags([])).effect!, at: 80).isEmpty)
        #expect(!schedule.isVisible && schedule.nextDeadline == nil)
    }
}

@Suite("Held menu rules (S-090, spec v18)")
struct HeldMenuRuleTests {
    func rules(_ entries: String) -> [String] {
        switch load(json(entries: entries, actions: minimalActions)) {
        case .success: []
        case let .failure(errors): errors.issues.map { "\($0.rule?.rawValue ?? "") \($0.subject ?? "")" }
        }
    }

    @Test("Hold reads, and the writer keeps it on leaders and leaves out false")
    func roundTrip() throws {
        let text = json(entries: """
        { "keys": "CAG+A", "title": "Apps", "hold": true },
        { "keys": "CAG+A T", "title": "Terminal", "action": "edit" },
        { "keys": "CAG+D", "title": "Window", "hold": false },
        { "keys": "CAG+D T", "title": "Terminal", "action": "edit" }
        """, actions: minimalActions)
        let loaded = try load(text).get()
        #expect(loaded.leaders.map(\.hold) == [true, false])
        let written = String(decoding: try ConfigDocument(data: Data(text.utf8)).data(), as: UTF8.self)
        #expect(written.contains(#"{ "keys": "CAG+A", "title": "Apps", "hold": true }"#))
        #expect(written.contains(#"{ "keys": "CAG+D", "title": "Window" }"#))
    }

    @Test("A key under a held leader can't be its menu's repeat key")
    func repeatKey() {
        #expect(rules("""
        { "keys": "CAG+D", "title": "Window", "hold": true },
        { "keys": "CAG+D D", "title": "Center", "action": "edit" }
        """) == ["step-is-repeat-key CAG+D D"])
        #expect(rules("""
        { "keys": "CAG+A", "title": "Apps", "hold": true },
        { "keys": "CAG+A B", "title": "More" },
        { "keys": "CAG+A B A", "title": "Fine", "action": "edit" },
        { "keys": "CAG+A B B", "title": "Not", "action": "edit" }
        """) == ["step-is-repeat-key CAG+A B B"])
        // Without Hold, the same key is fine.
        #expect(rules("""
        { "keys": "CAG+D", "title": "Window" },
        { "keys": "CAG+D D", "title": "Center", "action": "edit" }
        """).isEmpty)
    }

    @Test("Hold only on a leader with modifiers")
    func leaderOnly() {
        #expect(rules("""
        { "keys": "CAG+A", "title": "Apps" },
        { "keys": "CAG+A W", "title": "Windows", "hold": true },
        { "keys": "CAG+A W T", "title": "Terminal", "action": "edit" }
        """) == ["hold-not-leader CAG+A W"])
        #expect(rules(#"{ "keys": "CAG+T", "title": "Terminal", "action": "edit", "hold": true }"#) == ["hold-not-leader CAG+T"])
        #expect(rules("""
        { "keys": "F13", "title": "Apps", "hold": true },
        { "keys": "F13 T", "title": "Terminal", "action": "edit" }
        """) == ["hold-no-modifiers F13"])
    }
}
