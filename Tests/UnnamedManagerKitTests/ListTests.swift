import Foundation
import Testing
@testable import UnnamedManagerKit

private let cag: Modifiers = [.control, .option, .command]

private let entries = """
{ "keys": "CAG+H", "title": "Recent Windows", "hold": true, "list": { "type": "windows.recent" } },
{ "keys": "Hyper+W", "title": "Windows" },
{ "keys": "Hyper+W R", "title": "Recent", "list": { "type": "windows.recent", "count": 5, "spaces": "current" } },
{ "keys": "Hyper+W F", "title": "Fill", "action": "window-fill" }
"""

private func engine() throws -> SequenceEngine {
    SequenceEngine(config: try load(json(entries: entries)).get())
}

private func down(_ key: KeyName, _ modifiers: Modifiers = cag) -> KeyEvent {
    .down(keyCode: key.keyCode!, modifiers: modifiers, isRepeat: false)
}

private let items = [ListItem(id: 10, title: "Notes"), ListItem(id: 11, title: "Safari"), ListItem(id: 12, title: "Terminal")]
private let front = ListItem(id: 1, title: "Zed")

/// The highlight a held effect shows, with its menu's item titles.
private func held(_ effect: SequenceEffect?) -> (titles: [String], highlight: Int)? {
    guard case let .showHeld(menu, highlight, _, _) = effect else { return nil }
    return (menu.children.map(\.title), highlight)
}

private func ranItem(_ effect: SequenceEffect?) -> Int? {
    guard case let .run(node, _) = effect else { return nil }
    return node.item?.id
}

@Suite("Lists (S-092, spec v18)")
struct ListTests {
    @Test("A list reads and writes, with its defaults left out")
    func roundTrip() throws {
        let config = try load(json(entries: entries)).get().config
        #expect(config.entries[0].list == Config.List())
        #expect(config.entries[2].list == Config.List(count: 5, spaces: "current"))
        let text = ConfigWriter.write(config, actionOrder: [])
        #expect(text.contains(#""list": { "type": "windows.recent" }"#))
        #expect(text.contains(#""list": { "type": "windows.recent", "count": 5, "spaces": "current" }"#))
        #expect(try load(text).get().config == config)
    }

    @Test("A list's rules", arguments: [
        (#"{ "keys": "CAG+H", "title": "R", "list": { "type": "windows.recent" } }, { "keys": "CAG+H F", "title": "F", "action": "window-fill" }"#, "list-has-children CAG+H F"),
        (#"{ "keys": "CAG+H", "title": "R", "action": "window-fill", "list": { "type": "windows.recent" } }"#, "conflicting-fields CAG+H"),
        (#"{ "keys": "CAG+H", "title": "R", "list": { "type": "apps.running" } }"#, "unknown-list-type CAG+H"),
        (#"{ "keys": "CAG+H", "title": "R", "list": { "type": "windows.recent", "count": 0 } }"#, "bad-list-value CAG+H"),
        (#"{ "keys": "CAG+H", "title": "R", "list": { "type": "windows.recent", "scope": "space" } }"#, "bad-list-value CAG+H"),
        (#"{ "keys": "CAG+1", "title": "R", "hold": true, "list": { "type": "windows.recent" } }"#, "step-is-repeat-key CAG+1"),
    ])
    func rules(_ entries: String, _ rule: String) {
        switch load(json(entries: entries)) {
        case .success: Issue.record("\(entries) loaded")
        case let .failure(errors): #expect(errors.issues.map { "\($0.rule?.rawValue ?? "") \($0.subject ?? "")" } == [rule])
        }
    }

    @Test("A list without a type is a missing field, and a list is never an empty menu")
    func missingAndEmpty() throws {
        guard case let .failure(errors) = load(json(entries: #"{ "keys": "CAG+H", "title": "R", "list": { "count": 5 } }"#)) else {
            Issue.record("loaded")
            return
        }
        #expect(errors.issues.map(\.rule) == [.missingField])
        // A list that isn't held can have a digit for its key.
        _ = try load(json(entries: #"{ "keys": "CAG+1", "title": "R", "list": { "type": "windows.recent" } }"#)).get()
    }

    @Test("Opening a held list asks for its items, then shows them with the first highlighted")
    func fills() throws {
        var e = try engine()
        guard case .fillList = e.handle(down(.h)).effect else { Issue.record("no fill"); return }
        #expect(e.isFilling && !e.isHeld)
        let effects = e.fill(items, front: front)
        #expect(effects.count == 1)
        #expect(held(effects[0])! == (["Notes", "Safari", "Terminal"], 1))
        guard case let .showHeld(menu, _, _, _) = effects[0] else { return }
        #expect(menu.children.map { $0.path.lastStep!.key } == [.d1, .d2, .d3])
        #expect(menu.front == front)
    }

    @Test("Keys pressed before the items come are replayed: a fast CAG+H 2 and letting go")
    func replays() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        #expect(e.handle(down(.d2)).consume)
        #expect(!e.handle(.flags([])).consume)
        let effects = e.fill(items, front: front)
        #expect(effects.count == 3)
        #expect(held(effects[1])?.highlight == 2)
        #expect(ranItem(effects[2]) == 11)
        #expect(!e.isActive)
    }

    @Test("The repeat key and letting go choose an item")
    func chooses() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        _ = e.fill(items, front: front)
        #expect(held(e.handle(down(.h)).effect)?.highlight == 2)
        #expect(ranItem(e.handle(.flags([])).effect) == 11)
    }

    @Test("A held list with no items has only Cancel, and letting go cancels")
    func empty() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        #expect(held(e.fill([], front: front).first)! == ([], 0))
        #expect(e.handle(.flags([])).effect == .cancelled)
    }

    @Test("A list in a menu that isn't held runs an item by its key")
    func notHeld() throws {
        var e = try engine()
        _ = e.handle(down(.w, .hyper))
        guard case .fillList = e.handle(down(.r, [])).effect else { Issue.record("no fill"); return }
        guard case let .showMenu(menu, path, _) = e.fill(items, front: nil).first else { Issue.record("no menu"); return }
        #expect(menu.children.count == 3 && path == ["Windows", "Recent"])
        #expect(ranItem(e.handle(down(.d3, [])).effect) == 12)
    }

    @Test("When an item's window closes, the keys after it move up and the highlight moves on")
    func removes() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        _ = e.fill(items, front: front)
        _ = e.handle(down(.h))
        // The highlighted Safari goes: the next item, Terminal, takes its key and the highlight.
        let next = e.removeItem(id: 11)
        #expect(held(next)! == (["Notes", "Terminal"], 2))
        guard case let .showHeld(menu, _, _, _) = next else { return }
        #expect(menu.children.map { $0.path.lastStep!.key } == [.d1, .d2])
        // The last one goes: the one before.
        #expect(held(e.removeItem(id: 12))! == (["Notes"], 1))
        // An item before the highlight would move it up; the only one left goes: Cancel.
        #expect(held(e.removeItem(id: 10))! == ([], 0))
        #expect(e.removeItem(id: 99) == nil)
    }

    @Test("An item before the highlight moves the highlight up with its item")
    func removesBefore() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        _ = e.fill(items, front: front)
        _ = e.handle(down(.d3))
        #expect(held(e.removeItem(id: 10))! == (["Safari", "Terminal"], 2))
    }

    @Test("Recent Windows: the history first, then the others front first, without the focused window, filtered, at most count")
    func order() {
        let items = RecentWindows.items(history: ["A", "B", "C", "X"], front: ["D", "A", "E"], found: ["F", "E", "D", "B"],
                                        focused: "A", count: 4) { $0 != "C" }
        // C is filtered; D and E are in front, F after; X came from the history.
        #expect(items == ["B", "X", "D", "E"])
        #expect(RecentWindows.items(history: [], front: [], found: ["F"], focused: nil, count: 9) { _ in true } == ["F"])
        #expect(FocusHistory<Int>.limit >= 30)
    }

    @Test("Pages of 9, More on 0 on every page but the last, and the page in the path (S-093)")
    func pages() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        let many = (0..<20).map { ListItem(id: $0, title: "W\($0)") }
        guard case let .showHeld(first, 1, path, _) = e.fill(many, front: nil).first else { Issue.record("not held"); return }
        #expect(first.children.count == 9 && first.hasMore && path == ["Recent Windows", "Page 1 of 3"])
        guard case let .showHeld(second, 1, secondPath, _) = e.handle(down(.d0)).effect else { Issue.record("no More"); return }
        #expect(second.children.map(\.title).first == "W9" && second.children.map { $0.path.lastStep!.key }.first == .d1)
        #expect(secondPath == ["Recent Windows", "Page 2 of 3"])
        guard case let .showHeld(last, _, _, _) = e.handle(down(.d0)).effect else { Issue.record("no More"); return }
        #expect(last.children.map(\.title) == ["W18", "W19"] && !last.hasMore)
        // No More on the last page: 0 is an unbound key.
        guard case .unbound = e.handle(down(.d0)).effect else { Issue.record("0 did something"); return }
        // Back goes to the page before.
        guard case let .showHeld(back, _, _, _) = e.handle(down(.backspace, cag)).effect else { Issue.record("no Back"); return }
        #expect(back.page == 1)
        #expect(ranItem(e.handle(.flags([])).effect) == 9)
    }

    @Test("The repeat key goes from item 9 onto the next page, and after the last item to Cancel on the first page")
    func across() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        let many = (0..<11).map { ListItem(id: $0, title: "W\($0)") }
        _ = e.fill(many, front: nil)
        for _ in 1..<9 { _ = e.handle(down(.h)) }
        #expect(held(e.handle(down(.h)).effect)! == (["W9", "W10"], 1))
        #expect(held(e.handle(down(.down)).effect)! == (["W9", "W10"], 2))
        let cancel = held(e.handle(down(.h)).effect)!
        #expect(cancel.highlight == 0 && cancel.titles.count == 9)
        // Back from Cancel: the last item, on the last page.
        #expect(held(e.handle(down(.h, cag.union(.shift))).effect)! == (["W9", "W10"], 2))
    }

    @Test("Removing an item moves the later ones up across pages, and the highlight with them")
    func removesAcross() throws {
        var e = try engine()
        _ = e.handle(down(.h))
        _ = e.fill((0..<11).map { ListItem(id: $0, title: "W\($0)") }, front: nil)
        _ = e.handle(down(.d0))
        // W9 is highlighted, first on page 2; W0 goes, so W9 moves to item 9 of page 1.
        #expect(held(e.removeItem(id: 0))! == (["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9"], 9))
    }

    @Test("A list that isn't held pages with 0 too")
    func pagesNotHeld() throws {
        var e = try engine()
        _ = e.handle(down(.w, .hyper))
        _ = e.handle(down(.r, []))
        _ = e.fill((0..<12).map { ListItem(id: $0, title: "W\($0)") }, front: nil)
        guard case let .showMenu(menu, _, _) = e.handle(down(.d0, [])).effect else { Issue.record("no More"); return }
        #expect(menu.children.map(\.title) == ["W9", "W10", "W11"])
        #expect(ranItem(e.handle(down(.d2, [])).effect) == 10)
    }
}

@Suite("Hold to Choose and Contents in the editor (S-094)")
struct HoldEditingTests {
    @Test("Hold and a list set and clear, and a held menu's repeat key is refused as a key")
    func edits() throws {
        var d = ConfigDocument(config: try load(json(entries: """
        { "keys": "CAG+N", "title": "Next" },
        { "keys": "CAG+N X", "title": "Other", "action": "window-fill" },
        { "keys": "CAG+R", "title": "Recent", "list": { "type": "windows.recent" } }
        """)).get().config)
        let next = KeySequence(parsing: "CAG+N")!, other = KeySequence(parsing: "CAG+N X")!
        #expect(d.keyProblem(for: other, newKey: Chord(key: .n)) == nil)
        d.setHold(next, true)
        #expect(d.entry(next)?.hold == true)
        #expect(d.keyProblem(for: other, newKey: Chord(key: .n)) == .repeatKey("CAG+N"))
        d.setList(KeySequence(parsing: "CAG+R")!, nil)
        #expect(d.entry(KeySequence(parsing: "CAG+R")!)?.list == nil)
    }
}
