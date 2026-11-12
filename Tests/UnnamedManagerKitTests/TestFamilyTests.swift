import Foundation
import Testing
@testable import UnnamedManagerKit

/// A family only these tests know, added without touching a shared file:
/// proof that a new kind of action is one file plus one registry line (S-060).
struct BeepAction: ActionValue {
    var times: Int

    static let kinds = [ActionKind(type: "test.beep", displayName: "Beep", symbol: "speaker.wave.2")]
    var type: String { "test.beep" }

    static func blank(_ type: String) -> BeepAction { BeepAction(times: 1) }

    init(times: Int) { self.times = times }

    init(type: String, fields: ActionFields) throws {
        try fields.allow(["times"])
        times = try fields.value("times", default: 1)
        guard times > 0 else {
            throw fields.invalid("times", "“times” must be 1 or more.", rule: .wrongType)
        }
    }

    func write(to fields: inout ActionFieldWriter) {
        if times != 1 { fields.number("times", Double(times)) }
    }

    static func schema(_ type: String) -> ActionSchema {
        ActionSchema(["times": ["type": "integer", "minimum": 1]])
    }

    func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(BeepStep(times: times)))
    }
}

struct BeepStep: ActionStep {
    let times: Int
}

@Suite("A family added in a test (S-060)")
struct TestFamilyTests {
    static let registry = ActionRegistry.standard.adding(BeepAction.self)

    static let config = #"""
    { "version": 1,
      "entries": [ { "keys": "Cmd+Opt+B", "title": "Beep", "action": "beep" } ],
      "actions": { "beep": { "type": "test.beep", "times": 3 } } }
    """#

    @Test("A config that uses it loads and validates through the decoder's registry")
    func loads() throws {
        let loaded = try ConfigLoader.load(Data(Self.config.utf8), registry: Self.registry).get()
        #expect(loaded.config.actions["beep"] == .family(AnyActionValue(BeepAction(times: 3))))
        #expect(loaded.config.actions["beep"]?.displayName == "Beep")
    }

    @Test("The standard registry still rejects it as an unknown type")
    func unknownElsewhere() {
        guard case let .failure(errors) = ConfigLoader.load(Data(Self.config.utf8)) else {
            Issue.record("loaded without the family"); return
        }
        #expect(errors.issues.first?.rule == .unknownActionType)
    }

    @Test("Its own checks report under its own rule")
    func invalid() {
        let bad = Self.config.replacingOccurrences(of: #""times": 3"#, with: #""times": 0"#)
        guard case let .failure(errors) = ConfigLoader.load(Data(bad.utf8), registry: Self.registry) else {
            Issue.record("loaded a bad value"); return
        }
        #expect(errors.issues.first?.rule == .wrongType)
        #expect(errors.issues.first?.message.contains("“times” must be 1 or more.") == true)
    }

    @Test("The schema lists it before Context Aware")
    func schema() throws {
        #expect(ConfigSchema.actionTypes(registry: Self.registry).suffix(2) == ["test.beep", "contextual"])
        #expect(ConfigSchema.json(registry: Self.registry).contains(#""test.beep""#))
        #expect(!ConfigSchema.json(registry: .standard).contains(#""test.beep""#))
    }

    @Test("It writes and reads back the same, defaults left out")
    func roundTrip() throws {
        let three = Config.Action.family(AnyActionValue(BeepAction(times: 3)))
        #expect(try ActionRegistryTests.decode(ConfigWriter.action(three, contexts: []), registry: Self.registry) == three)
        #expect(ConfigWriter.action(.family(AnyActionValue(BeepAction(times: 1))), contexts: []) == #"{ "type": "test.beep" }"#)
    }

    @Test("It plans its own step, and its kind's symbol is its icon")
    func plan() throws {
        let action = Config.Action.family(AnyActionValue(BeepAction(times: 2)))
        #expect(try ActionPlanner.plan(action, home: testHome) == .custom(AnyActionStep(BeepStep(times: 2))))
        #expect(BeepAction(times: 2).iconSource(home: testHome) == .symbol("speaker.wave.2"))
    }
}
