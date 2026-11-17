import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Focus or swap with the window used before, and leave apps out (S-083, spec v13)")
struct FocusHistoryTests {
    @Test("A window goes first each time it gets focus, once, and the history keeps 10")
    func record() {
        var history = FocusHistory<Int>()
        for window in [1, 2, 3, 2] { history.record(window) }
        #expect(history.windows == [2, 3, 1])
        for window in 10..<25 { history.record(window) }
        #expect(history.windows == Array((15..<25).reversed()))
    }

    @Test("The window used before is the first that isn't the focused one and still counts")
    func recent() {
        var history = FocusHistory<String>()
        for window in ["a", "b", "c"] { history.record(window) }
        #expect(history.recent(before: "c") { _ in true } == "b")
        // b was closed, so it's the one before that.
        #expect(history.recent(before: "c") { $0 != "b" } == "a")
        #expect(history.recent(before: nil) { _ in true } == "c")
        #expect(history.recent(before: "c") { $0 == "c" } == nil)
        #expect(FocusHistory<String>().recent(before: nil) { _ in true } == nil)
    }

    @Test("recent is a target of Focus Window and Swap Window, with built-in names and the old field name")
    func target() throws {
        #expect(BuiltInAction.action(named: "window-focus-recent") == .family(AnyActionValue(FocusAction(.recent))))
        #expect(BuiltInAction.action(named: "window-swap-recent") == .family(AnyActionValue(SwapAction(.window(.recent)))))
        let minimal = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W" }, { "keys": "Meh+W H", "title": "H", "action": "h" } ], "actions": { "h": { "type": "window.focus", "direction": "recent" } } }"#
        let loaded = try ConfigLoader.load(Data(minimal.utf8)).get()
        #expect(ConfigWriter.write(loaded.config, actionOrder: []).contains(#"{ "type": "window.focus", "direction": "recent" }"#))
    }

    @Test("windows.exclude is empty by default, written only when it isn't, and must be a list of text")
    func exclude() throws {
        let minimal = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W" }, { "keys": "Meh+W H", "title": "H", "action": "window-focus-recent" } ]"#
        let plain = try ConfigLoader.load(Data((minimal + " }").utf8)).get()
        #expect(plain.config.windows.exclude.isEmpty)
        #expect(!ConfigWriter.write(plain.config, actionOrder: []).contains("windows"))
        let set = try ConfigLoader.load(Data((minimal + #", "windows": { "exclude": ["com.apple.finder"] } }"#).utf8)).get()
        #expect(set.config.windows.exclude == ["com.apple.finder"])
        #expect(ConfigWriter.write(set.config, actionOrder: []).contains(#""windows": { "exclude": ["com.apple.finder"] }"#))
        guard case let .failure(errors) = ConfigLoader.load(Data((minimal + #", "windows": { "exclude": "com.apple.finder" } }"#).utf8)) else {
            Issue.record("loaded an exclude that isn't a list"); return
        }
        #expect(errors.issues.first?.rule == .wrongType)
    }
}
