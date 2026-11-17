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

    @Test("windows.apps is empty by default, and an app's missing rules are true (S-084, spec v15)")
    func apps() throws {
        let plain = try ConfigLoader.load(Data((Self.minimal + " }").utf8)).get()
        #expect(plain.config.windows.apps.isEmpty)
        #expect(!ConfigWriter.write(plain.config, actionOrder: []).contains("windows"))
        let set = try ConfigLoader.load(Data((Self.minimal + #", "windows": { "apps": { "com.apple.calculator": { "arrange": false }, "com.apple.Notes": {} } } }"#).utf8)).get()
        #expect(set.config.windows.apps == ["com.apple.calculator": .init(arrange: false), "com.apple.Notes": .init()])
        #expect(set.config.windows.leftOut(of: \.arrange) == ["com.apple.calculator"])
        #expect(set.config.windows.leftOut(of: \.focus).isEmpty)
    }

    @Test("Every listed app is written with all three rules, sorted, even with every rule true")
    func appsWritten() throws {
        var windows = Config.Windows(apps: ["com.apple.finder": .init(focus: false, swap: false), "com.apple.calculator": .init(arrange: false)])
        var config = try ConfigLoader.load(Data((Self.minimal + " }").utf8)).get().config
        config.windows = windows
        #expect(ConfigWriter.write(config, actionOrder: []).contains(#""windows": { "apps": { "com.apple.calculator": { "focus": true, "swap": true, "arrange": false }, "com.apple.finder": { "focus": false, "swap": false, "arrange": true } } }"#))
        windows.apps["com.apple.calculator"]?.arrange = true
        config.windows = windows
        #expect(ConfigWriter.write(config, actionOrder: []).contains(#""com.apple.calculator": { "focus": true, "swap": true, "arrange": true }"#))
    }

    @Test("A rule that isn't one is unknown-field, one that isn't a boolean is wrong-type, and windows.exclude is gone")
    func appsRejected() {
        #expect(rule(#""apps": ["com.apple.calculator"]"#) == .wrongType)
        #expect(rule(#""apps": { "com.apple.calculator": { "arrange": "no" } }"#) == .wrongType)
        #expect(rule(#""apps": { "com.apple.calculator": { "float": true } }"#) == .unknownField)
        #expect(rule(#""exclude": ["com.apple.finder"]"#) == .unknownField)
    }

    static let minimal = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W" }, { "keys": "Meh+W H", "title": "H", "action": "window-focus-recent" } ]"#

    /// The rule a windows setting breaks.
    func rule(_ setting: String) -> ConfigRule? {
        guard case let .failure(errors) = ConfigLoader.load(Data((Self.minimal + #", "windows": { "# + setting + " } }").utf8)) else { return nil }
        return errors.issues.first?.rule
    }
}
