import CoreGraphics
import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Swap a window with another (S-077, spec v10)")
struct SwapTests {
    static let screens = [
        WindowGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), usable: CGRect(x: 0, y: 25, width: 1440, height: 875)),
        WindowGeometry.Screen(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), usable: CGRect(x: 1440, y: 25, width: 1920, height: 1055)),
    ]
    // In Focus Window's order: two halves of the left display, then the right display.
    static let a = CGRect(x: 0, y: 25, width: 720, height: 875)
    static let b = CGRect(x: 720, y: 25, width: 720, height: 875)
    static let c = CGRect(x: 1440, y: 25, width: 1920, height: 1055)

    /// The pick for the window at `current`, among windows given in reverse
    /// order so the result can't just be the input order.
    func pick(_ target: WindowTarget, from current: Int?, _ windows: [CGRect] = [c, b, a]) -> SwapPick {
        let frame = current.map { windows[$0] } ?? .zero
        return WindowGeometry.swapPartner(target, current: current, frame: frame, windows: windows,
                                          owners: windows.map { _ in 1 }, screens: Self.screens)
    }

    @Test("A direction picks the window Focus Window would focus, across displays")
    func directions() {
        #expect(pick(.window(.left), from: 1) == .window(2))
        #expect(pick(.window(.right), from: 1) == .window(0))
        #expect(pick(.window(.left), from: 0) == .window(1))
    }

    @Test("With no window that way, it says which way")
    func noneThatWay() {
        #expect(pick(.window(.left), from: 2) == .none("No window to the left."))
        #expect(pick(.window(.up), from: 1) == .none("No window above."))
        #expect(pick(.window(.right), from: 0) == .none("No window to the right."))
    }

    @Test("Next and Previous wrap at the ends, and need another window")
    func cycle() {
        #expect(pick(.window(.next), from: 0) == .window(2))
        #expect(pick(.window(.previous), from: 2) == .window(0))
        #expect(pick(.window(.next), from: 1) == .window(0))
        #expect(pick(.window(.next), from: 0, [Self.a]) == .none("No other window to swap with."))
    }

    @Test("First, Last and numbers count in Focus Window's order, from 1")
    func numbers() {
        #expect(pick(.window(.first), from: 0) == .window(2))
        #expect(pick(.window(.last), from: 2) == .window(0))
        #expect(pick(.number(1), from: 0) == pick(.window(.first), from: 0))
        #expect(pick(.number(2), from: 0) == .window(1))
        #expect(pick(.number(3), from: 2) == .window(0))
    }

    @Test("A target that is the focused window does nothing, and isn't a failure")
    func stay() {
        #expect(pick(.window(.first), from: 2) == .stay)
        #expect(pick(.window(.last), from: 0) == .stay)
        #expect(pick(.number(2), from: 1) == .stay)
    }

    @Test("A number past the last window says how many there are")
    func pastTheEnd() {
        #expect(pick(.number(4), from: 0) == .none("No window 4. There are 3."))
        #expect(pick(.number(2), from: 0, [Self.a]) == .none("No window 2. There is 1."))
        #expect(pick(.window(.first), from: nil, []) == .none("No window to swap with."))
    }

    @Test("A swap left and then right puts two windows back where they were")
    func inverse() {
        // After the first swap, the focused window (1) has the other's frame, and the other (2) has its frame.
        #expect(pick(.window(.left), from: 1) == .window(2))
        #expect(pick(.window(.right), from: 1, [Self.c, Self.a, Self.b]) == .window(2))
    }

    @Test("It reads, writes and plans as the spec says, the default scope left out")
    func family() throws {
        let left = try ActionRegistryTests.decode(#"{ "type": "window.swap", "target": "left" }"#)
        #expect(left == .family(AnyActionValue(SwapAction(.window(.left)))))
        #expect(left.displayName == "Swap Window")
        #expect(try ActionPlanner.plan(left, home: testHome) == .custom(AnyActionStep(WindowCommand.swap(.window(.left)))))
        let two = #"{ "type": "window.swap", "target": 2, "scope": "display" }"#
        let numbered = try ActionRegistryTests.decode(two)
        #expect(numbered == .family(AnyActionValue(SwapAction(.number(2), scope: .display))))
        #expect(ConfigWriter.action(numbered, contexts: []) == two)
        let everywhere = try ActionRegistryTests.decode(#"{ "type": "window.swap", "target": "first", "scope": "all" }"#)
        #expect(ConfigWriter.action(everywhere, contexts: []) == #"{ "type": "window.swap", "target": "first" }"#)
    }

    @Test("Each kind of target shows its own symbol")
    func icons() {
        #expect(SwapAction(.window(.right)).iconSource(home: testHome) == .symbol("arrow.left.arrow.right.square"))
        #expect(SwapAction(.window(.down)).iconSource(home: testHome) == .symbol("arrow.up.arrow.down.square"))
        #expect(SwapAction(.number(3)).iconSource(home: testHome) == .symbol("number.square"))
        #expect(SwapAction(.window(.next)).iconSource(home: testHome) == .symbol("rectangle.2.swap"))
    }
}

@Suite("Focus Window on one display (S-078, spec v10)")
struct FocusScopeTests {
    @Test("scope reads, writes and plans, and every display is the default")
    func family() throws {
        let json = #"{ "type": "window.focus", "target": "next", "scope": "display" }"#
        let here = try ActionRegistryTests.decode(json)
        #expect(here == .family(AnyActionValue(FocusAction(.next, scope: .display))))
        #expect(ConfigWriter.action(here, contexts: []) == json)
        #expect(try ActionPlanner.plan(here, home: testHome) == .custom(AnyActionStep(WindowCommand.focus(.window(.next), scope: .display))))
        let plain = try ActionRegistryTests.decode(#"{ "type": "window.focus", "target": "next" }"#)
        #expect(plain == .family(AnyActionValue(FocusAction(.next, scope: .all))))
    }

    @Test("A failure plays no sound unless it says so")
    func alerts() {
        #expect(!PlanError("No app is in front.").alerts)
        #expect(PlanError("No window to the left.", alerts: true).alerts)
    }
}
