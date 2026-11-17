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

    @Test("windows.exclude is empty by default, written only when it isn't, and the v13 list loads as focus and is written back as a list")
    func exclude() throws {
        let plain = try ConfigLoader.load(Data((Self.minimal + " }").utf8)).get()
        #expect(plain.config.windows.exclude.isEmpty)
        #expect(!ConfigWriter.write(plain.config, actionOrder: []).contains("windows"))
        var list = try ConfigLoader.load(Data((Self.minimal + #", "windows": { "exclude": ["com.apple.finder"] } }"#).utf8)).get().config
        #expect(list.windows.exclude == .init(focus: ["com.apple.finder"]))
        #expect(ConfigWriter.write(list, actionOrder: []).contains(#""windows": { "exclude": ["com.apple.finder"] }"#))
        // Once arrange has an app, only the object can say it.
        list.windows.exclude.set("com.apple.calculator", in: \.arrange, true)
        #expect(ConfigWriter.write(list, actionOrder: []).contains(#""exclude": { "focus": ["com.apple.finder"], "arrange": ["com.apple.calculator"] }"#))
        #expect(rule(#""exclude": "com.apple.finder""#) == .wrongType)
    }

    @Test("windows.exclude has two separate lists, focus and arrange, and no other field (S-084, spec v14)")
    func excludeLists() throws {
        let set = try ConfigLoader.load(Data((Self.minimal + #", "windows": { "exclude": { "arrange": ["com.apple.calculator"] } } }"#).utf8)).get()
        #expect(set.config.windows.exclude == .init(arrange: ["com.apple.calculator"]))
        #expect(set.config.windows.exclude.apps == ["com.apple.calculator"])
        #expect(ConfigWriter.write(set.config, actionOrder: []).contains(#""windows": { "exclude": { "arrange": ["com.apple.calculator"] } }"#))
        #expect(rule(#""exclude": { "arrange": "com.apple.calculator" }"#) == .wrongType)
        #expect(rule(#""exclude": { "swap": [] }"#) == .unknownField)
        var both = Config.Windows.Exclude(focus: ["a", "b"], arrange: ["b", "c"])
        #expect(both.apps == ["a", "b", "c"])
        both.set("b", in: \.focus, false)
        #expect(both.focus == ["a"] && both.apps == ["a", "b", "c"])
    }

    static let minimal = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W" }, { "keys": "Meh+W H", "title": "H", "action": "window-focus-recent" } ]"#

    /// The rule a windows setting breaks.
    func rule(_ setting: String) -> ConfigRule? {
        guard case let .failure(errors) = ConfigLoader.load(Data((Self.minimal + #", "windows": { "# + setting + " } }").utf8)) else { return nil }
        return errors.issues.first?.rule
    }
}
