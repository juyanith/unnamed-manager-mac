import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Built-in actions (S-079, spec v11)")
struct BuiltInActionTests {
    func named(_ name: String) -> Config.Action? {
        BuiltInAction.action(named: name)
    }

    @Test("Each name stands for its type with one value of its main field, and every other field at its default")
    func names() {
        #expect(named("window-fill") == .family(AnyActionValue(FillAction())))
        #expect(named("window-minimize") == .family(AnyActionValue(MinimizeAction())))
        #expect(named("window-place-left-half") == .family(AnyActionValue(PlaceAction.preset(.leftHalf))))
        #expect(named("window-place-left-two-thirds") == .family(AnyActionValue(PlaceAction.preset(.leftTwoThirds))))
        #expect(named("window-resize-grow") == .family(AnyActionValue(ResizeAction(.step(.grow, widths: nil)))))
        #expect(named("window-arrange") == .family(AnyActionValue(ArrangeAction())))
        #expect(named("window-arrange-3") == .family(AnyActionValue(ArrangeAction(count: .windows(3)))))
        #expect(named("window-arrange-all") == .family(AnyActionValue(ArrangeAction(count: .all))))
        #expect(named("window-focus-left") == .family(AnyActionValue(FocusAction(.left))))
        #expect(named("window-focus-2") == .family(AnyActionValue(FocusAction(.number(2)))))
        #expect(named("window-swap-first") == .family(AnyActionValue(SwapAction(.window(.first)))))
        #expect(named("window-swap-12") == .family(AnyActionValue(SwapAction(.number(12)))))
        #expect(named("help") == .family(AnyActionValue(BasicAction.help)))
        #expect(named("noop") == .family(AnyActionValue(BasicAction.noop)))
    }

    @Test("Names that aren't built in", arguments: [
        "window-place-left-hlf", "window-place-leftHalf", "Window-Fill", "window-swap-0", "window-focus-02",
        "window-arrange-9", "window-arrange-1", "window-maximize", "window-fill-on", "window-place", "window-move",
        "application", "window-place-left--half", "window-swap-", "window-focus-٣",
    ])
    func rejected(_ name: String) {
        #expect(named(name) == nil)
    }

    @Test("The listed names all stand for their own action, with none twice and no numbers past Arrange Windows' eight")
    func entries() {
        let entries = BuiltInAction.entries()
        #expect(entries.allSatisfy { named($0.name) == $0.action })
        #expect(Set(entries.map(\.name)).count == entries.count)
        #expect(entries.map(\.name).contains("window-place-bottom-right"))
        #expect(entries.map(\.name).contains("window-swap-last"))
        #expect(!entries.map(\.name).contains("window-swap-1"))
        #expect(entries.count == 1 + 1 + 14 + 2 + 8 + 9 + 9 + 2 + 2)
    }

    @Test("An action in actions with a built-in name overrides it, and any other name falls back to the built-in")
    func overrides() throws {
        let json = #"""
        { "version": 1,
          "entries": [{ "keys": "Meh+A", "title": "Left", "action": "window-focus-left" },
                      { "keys": "Meh+B", "title": "Right", "action": "window-focus-right" }],
          "actions": { "window-focus-left": { "type": "exec", "command": ["yabai", "-m", "window", "--focus", "west"] } } }
        """#
        let config = try ConfigDocument(data: Data(json.utf8)).config
        #expect(config.action(named: "window-focus-left") == config.actions["window-focus-left"])
        #expect(config.action(named: "window-focus-right") == .family(AnyActionValue(FocusAction(.right))))
        #expect(Config.overridesBuiltIn("window-focus-left") && !Config.overridesBuiltIn("left-half"))
        let loaded = try ConfigLoader.load(Data(json.utf8)).get()
        #expect(loaded.warnings.isEmpty)
    }

    @Test("A value in camel case is written in lowercase words, and back")
    func words() {
        #expect(BuiltInAction.words("leftTwoThirds") == "left-two-thirds")
        #expect(BuiltInAction.value("left-two-thirds") == "leftTwoThirds")
        #expect(BuiltInAction.prefix("window.place") == "window-place")
    }
}

@Suite("Focus Window's target (S-079, spec v11)")
struct FocusTargetTests {
    @Test("target takes a number, and direction, its old name, loads and is written back as the file had it")
    func oldName() throws {
        let number = #"{ "type": "window.focus", "target": 2 }"#
        let two = try ActionRegistryTests.decode(number)
        #expect(two == .family(AnyActionValue(FocusAction(.number(2)))))
        #expect(ConfigWriter.action(two, contexts: []) == number)
        let old = #"{ "type": "window.focus", "direction": "left" }"#
        let left = try ActionRegistryTests.decode(old)
        #expect(left == .family(AnyActionValue(FocusAction(.window(.left), field: "direction"))))
        #expect(ConfigWriter.action(left, contexts: []) == old)
        #expect(try ActionPlanner.plan(left, home: testHome) == .custom(AnyActionStep(WindowCommand.focus(.window(.left)))))
    }

    @Test("Both names, or a number below 1, is rejected")
    func rejected() {
        #expect(throws: (any Error).self) { try ActionRegistryTests.decode(#"{ "type": "window.focus", "target": "left", "direction": "left" }"#) }
        #expect(throws: (any Error).self) { try ActionRegistryTests.decode(#"{ "type": "window.focus", "target": 0 }"#) }
        #expect(throws: (any Error).self) { try ActionRegistryTests.decode(#"{ "type": "window.focus" }"#) }
    }

    @Test("A number past the end says how many windows there are")
    func pastTheEnd() {
        #expect(WindowTarget.pastTheEnd(5, count: 3) == "No window 5. There are 3.")
        #expect(WindowTarget.pastTheEnd(2, count: 1) == "No window 2. There is 1.")
        #expect(FocusAction(.number(4)).iconSource(home: testHome) == .symbol("number.circle"))
    }
}
