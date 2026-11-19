import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Switch Space (S-088, spec v17)")
struct SpaceSwitchTests {
    func load(_ action: String) -> Result<LoadedConfig, ConfigErrors> {
        ConfigLoader.load(Data((FocusHistoryTests.minimal + #", "actions": { "go": "# + action + " } }").utf8))
    }

    func rule(_ action: String) -> ConfigRule? {
        if case let .failure(error) = load(action) { error.issues.first?.rule } else { nil }
    }

    @Test("Reads and writes target left and right")
    func readWrite() throws {
        for direction in SpaceDirection.allCases {
            let loaded = try load(#"{ "type": "space.switch", "target": "\#(direction.rawValue)" }"#).get()
            #expect(loaded.config.actions["go"] == .family(AnyActionValue(SpaceSwitchAction(direction))))
            #expect(ConfigWriter.write(loaded.config, actionOrder: ["go"])
                .contains(#""go": { "type": "space.switch", "target": "\#(direction.rawValue)" }"#))
        }
    }

    @Test("No target is missing-field; another word or a number is bad-window-value; true is wrong-type")
    func rules() {
        #expect(rule(#"{ "type": "space.switch" }"#) == .missingField)
        #expect(rule(#"{ "type": "space.switch", "target": "up" }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.switch", "target": 2 }"#) == .badWindowValue)
        #expect(rule(#"{ "type": "space.switch", "target": true }"#) == .wrongType)
        #expect(rule(#"{ "type": "space.switch", "target": "left", "scope": "all" }"#) == .unknownField)
    }

    @Test("space-switch-left and space-switch-right are built-in actions; space-switch-up isn't")
    func builtIns() {
        #expect(BuiltInAction.action(named: "space-switch-left") == .family(AnyActionValue(SpaceSwitchAction(.left))))
        #expect(BuiltInAction.action(named: "space-switch-right") == .family(AnyActionValue(SpaceSwitchAction(.right))))
        #expect(BuiltInAction.action(named: "space-switch-up") == nil)
        #expect(BuiltInAction.action(named: "space-switch") == nil)
        #expect(BuiltInAction.entries().filter { $0.name.hasPrefix("space-switch") }.map(\.name) == ["space-switch-left", "space-switch-right"])
    }

    @Test("It plans a SpaceCommand for its direction")
    func plan() throws {
        #expect(try SpaceSwitchAction(.left).plan(home: URL(filePath: "/")) == .custom(AnyActionStep(SpaceCommand(direction: .left))))
    }

    @Test("A switch is Began, Changed and Ended dock swipes, horizontal")
    func events() {
        for payload in [false, true] {
            let events = DockSwipe.events(.right, payload: payload)
            #expect(events.map(\.phase) == [.began, .changed, .ended])
            for event in events {
                #expect(event.integers[DockSwipe.typeField] == DockSwipe.dockControlType)
                #expect(event.integers[DockSwipe.Field.hidType] == 23)
                #expect(event.integers[DockSwipe.Field.motion] == 1)
                #expect(event.integers[DockSwipe.Field.phase] == event.phase.rawValue)
            }
        }
    }

    @Test("Ended carries the high velocity for its direction: ±400 before macOS 27, ∓9999 from it")
    func velocity() {
        #expect(DockSwipe.events(.right, payload: false).last?.doubles[DockSwipe.Field.velocityX] == 400)
        #expect(DockSwipe.events(.left, payload: false).last?.doubles[DockSwipe.Field.velocityX] == -400)
        #expect(DockSwipe.events(.right, payload: true).last?.doubles[DockSwipe.Field.velocityX] == -9999)
        #expect(DockSwipe.events(.left, payload: true).last?.doubles[DockSwipe.Field.velocityX] == 9999)
        #expect(DockSwipe.events(.right, payload: true).first?.doubles[DockSwipe.Field.velocityX] == nil)
        #expect(DockSwipe.needsPayload(osMajor: 27) && !DockSwipe.needsPayload(osMajor: 26))
    }

    @Test("Before macOS 27, the direction is the smallest float's bits, signed")
    func flagBits() {
        #expect(DockSwipe.events(.right, payload: false)[0].integers[DockSwipe.Field.flagBits] == 1)
        #expect(DockSwipe.events(.left, payload: false)[0].integers[DockSwipe.Field.flagBits] == Int64(Int32(bitPattern: 0x8000_0001)))
    }

    @Test("The payload is a 28-byte header, a 40-byte gesture, and a 28-byte velocity when it moves or ends")
    func payload() {
        let events = DockSwipe.events(.right, payload: true, time: 7)
        let began = DockSwipe.payload(for: events[0], timestamp: 0x0102)
        #expect(began.count == 28 + 40)
        #expect(Array(began[0 ..< 8]) == [0x02, 0x01, 0, 0, 0, 0, 0, 0])
        #expect(began[24] == 1)  // event count
        #expect(Array(began[28 ..< 36]) == [40, 0, 0, 0, 23, 0, 0, 0])
        #expect(Array(began[36 ..< 40]) == [0, 0, 0, 1])  // phase 1 in the top byte
        #expect(Array(began[44 ..< 48]) == [0x99, 0x19, 0, 0])  // x 0.1 in 16.16
        #expect(Array(began[60 ..< 64]) == [1, 0, 3, 0])  // horizontal, the Dock's gesture
        #expect(Array(began[64 ..< 68]) == [0, 0, 0xFF, 0xFF])  // progress -1
        let ended = DockSwipe.payload(for: events[2], timestamp: 0)
        #expect(ended.count == 28 + 40 + 28)
        #expect(ended[24] == 2)
        #expect(Array(ended[68 ..< 72]) == [28, 0, 0, 0])
        #expect(ended[80] == 1)  // depth
        #expect(Array(ended[84 ..< 88]) == withUnsafeBytes(of: Int32(-9999 * 65536).littleEndian, Array.init))
    }

    @Test("16.16 keeps tiny values nonzero")
    func fixed() {
        #expect(DockSwipe.fixed(1) == 65536)
        #expect(DockSwipe.fixed(1e-9) == 1)
        #expect(DockSwipe.fixed(-1e-9) == -1)
        #expect(DockSwipe.fixed(0) == 0)
    }

    @Test("The payload goes after the event's data as field 4205, only on data version 2")
    func appending() {
        #expect(DockSwipe.appending([9, 9], to: [0, 0, 0, 2, 5]) == [0, 0, 0, 2, 5, 0, 2, 0x10, 0x6D, 9, 9])
        #expect(DockSwipe.appending([9], to: [0, 0, 0, 3]) == nil)
        #expect(DockSwipe.appending([9], to: [0, 0]) == nil)
    }
}
