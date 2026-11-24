import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Send to Space (S-096, spec v20) and Follow to Space (S-098, spec v23)")
struct SpaceSendTests {
    func load(_ action: String) -> Result<LoadedConfig, ConfigErrors> {
        ConfigLoader.load(Data((FocusHistoryTests.minimal + #", "actions": { "go": "# + action + " } }").utf8))
    }

    func rule(_ action: String) -> ConfigRule? {
        if case let .failure(error) = load(action) { error.issues.first?.rule } else { nil }
    }

    @Test("Reads and writes left, right and numbers, for Send to Space and Follow to Space")
    func readWrite() throws {
        let cases: [(String, SpaceSendAction)] = [
            (#"{ "type": "space.send", "target": "left" }"#, SpaceSendAction(.side(.left))),
            (#"{ "type": "space.send", "target": "right" }"#, SpaceSendAction(.side(.right))),
            (#"{ "type": "space.send", "target": 2 }"#, SpaceSendAction(.number(2))),
            (#"{ "type": "space.follow", "target": 3 }"#, SpaceSendAction(.number(3), follow: true)),
            (#"{ "type": "space.follow", "target": "left" }"#, SpaceSendAction(.side(.left), follow: true)),
        ]
        for (json, action) in cases {
            let loaded = try load(json).get()
            #expect(loaded.config.actions["go"] == .family(AnyActionValue(action)))
            #expect(String(decoding: try ConfigDocument(config: loaded.config).data(), as: UTF8.self).contains(#""go": \#(json)"#))
        }
    }

    @Test("A missing or bad target is rejected, and follow and send are unknown fields")
    func rules() {
        #expect(rule(#"{ "type": "space.send" }"#) == .missingField)
        #expect(rule(#"{ "type": "space.send", "target": 0 }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.send", "target": -1 }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.send", "target": 1.5 }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.send", "target": "up" }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.send", "target": "2" }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.send", "target": true }"#) == .wrongType)
        #expect(rule(#"{ "type": "space.send", "target": 2, "follow": true }"#) == .unknownField)
        #expect(rule(#"{ "type": "space.send", "target": 2, "follow": false }"#) == .unknownField)
        #expect(rule(#"{ "type": "space.follow" }"#) == .missingField)
        #expect(rule(#"{ "type": "space.follow", "target": 0 }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.follow", "target": "2" }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.follow", "target": 2, "send": true }"#) == .unknownField)
        #expect(rule(#"{ "type": "space.send", "target": 2, "scope": "all" }"#) == .unknownField)
    }

    @Test("space-send- and space-follow- left, right and N are built-in actions; -0 and -up aren't")
    func builtIns() {
        #expect(BuiltInAction.action(named: "space-send-left") == .family(AnyActionValue(SpaceSendAction(.side(.left)))))
        #expect(BuiltInAction.action(named: "space-send-right") == .family(AnyActionValue(SpaceSendAction(.side(.right)))))
        #expect(BuiltInAction.action(named: "space-send-12") == .family(AnyActionValue(SpaceSendAction(.number(12)))))
        for name in ["space-send-0", "space-send-02", "space-send-up", "space-send"] {
            #expect(BuiltInAction.action(named: name) == nil)
        }
        #expect(BuiltInAction.entries().filter { $0.name.hasPrefix("space-send") }.map(\.name) == ["space-send-left", "space-send-right"])
        #expect(BuiltInAction.action(named: "space-follow-left") == .family(AnyActionValue(SpaceSendAction(.side(.left), follow: true))))
        #expect(BuiltInAction.action(named: "space-follow-2") == .family(AnyActionValue(SpaceSendAction(.number(2), follow: true))))
        #expect(BuiltInAction.action(named: "space-follow-0") == nil)
        #expect(BuiltInAction.entries().filter { $0.name.hasPrefix("space-follow") }.map(\.name) == ["space-follow-left", "space-follow-right"])
    }

    @Test("It plans a SpaceSendCommand")
    func plan() throws {
        #expect(try SpaceSendAction(.number(2), follow: true).plan(home: URL(filePath: "/"))
            == .custom(AnyActionStep(SpaceSendCommand(target: .number(2), follow: true))))
    }

    @Test("Left and right stop at the ends, numbers past the last fail, the same Space stays")
    func pick() {
        let middle = DesktopPlace.desktop(2, of: 4)
        #expect(SpaceSend.pick(.side(.left), from: middle, appName: "Safari") == .desktop(1))
        #expect(SpaceSend.pick(.side(.right), from: middle, appName: "Safari") == .desktop(3))
        #expect(SpaceSend.pick(.side(.left), from: .desktop(1, of: 4), appName: "Safari") == .stay)
        #expect(SpaceSend.pick(.side(.right), from: .desktop(4, of: 4), appName: "Safari") == .stay)
        #expect(SpaceSend.pick(.number(4), from: middle, appName: "Safari") == .desktop(4))
        #expect(SpaceSend.pick(.number(2), from: middle, appName: "Safari") == .stay)
        #expect(SpaceSend.pick(.number(5), from: middle, appName: "Safari") == .none("No Space 5. There are 4."))
        #expect(SpaceSend.pick(.number(2), from: .desktop(1, of: 1), appName: "Safari") == .none("No Space 2. There is 1."))
        #expect(SpaceSend.pick(.number(1), from: .fullScreen, appName: "Safari")
            == .none("Safari's window is full screen, so it can't go to another Space."))
        #expect(SpaceSend.pick(.number(1), from: .everySpace, appName: "Safari") == .none("Safari's window is on every Space."))
    }
}
