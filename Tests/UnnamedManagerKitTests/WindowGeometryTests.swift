import CoreGraphics
import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Window geometry (spec v2)")
struct WindowGeometryTests {
    static let laptop = WindowGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                              usable: CGRect(x: 0, y: 33, width: 1512, height: 949))
    static let right = WindowGeometry.Screen(frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
                                             usable: CGRect(x: 1512, y: -175, width: 2560, height: 1415))

    @Test("The screen is the one that holds most of the window")
    func screen() {
        let screens = [Self.laptop, Self.right]
        #expect(WindowGeometry.screen(for: CGRect(x: 100, y: 100, width: 800, height: 600), among: screens) == Self.laptop)
        #expect(WindowGeometry.screen(for: CGRect(x: 1200, y: 100, width: 800, height: 600), among: screens) == Self.right)
        #expect(WindowGeometry.screen(for: CGRect(x: 1000, y: 100, width: 800, height: 600), among: screens) == Self.laptop)
    }

    @Test("A window on no screen uses the main one")
    func offScreen() {
        #expect(WindowGeometry.screen(for: CGRect(x: -5000, y: 0, width: 10, height: 10), among: [Self.laptop, Self.right]) == Self.laptop)
    }

    @Test("Cocoa rects flip to top-left coordinates, for displays above and below")
    func flip() {
        // The main display is 982 high. One above it starts at Cocoa y 982.
        #expect(WindowGeometry.topLeft(CGRect(x: 0, y: 0, width: 1512, height: 949), primaryHeight: 982)
                == CGRect(x: 0, y: 33, width: 1512, height: 949))
        #expect(WindowGeometry.topLeft(CGRect(x: 0, y: 982, width: 1920, height: 1080), primaryHeight: 982)
                == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(WindowGeometry.topLeft(CGRect(x: -200, y: -1080, width: 1920, height: 1080), primaryHeight: 982)
                == CGRect(x: -200, y: 982, width: 1920, height: 1080))
    }
}

@Suite("Maximize (S-062)")
struct MaximizeTests {
    static let usable = CGRect(x: 0, y: 33, width: 1512, height: 949)
    static let small = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test("A window that doesn't fill the usable area fills it")
    func fill() {
        var memory = MaximizeMemory<Int>()
        #expect(memory.step(for: 1, frame: Self.small, usable: Self.usable, toggle: true) == .fill(Self.usable))
    }

    @Test("Maximize again goes back to the frame from before")
    func restore() {
        var memory = MaximizeMemory<Int>()
        _ = memory.step(for: 1, frame: Self.small, usable: Self.usable, toggle: true)
        memory.record(1, before: Self.small, after: Self.usable)
        #expect(memory.step(for: 1, frame: Self.usable.insetBy(dx: 1, dy: 1), usable: Self.usable, toggle: true) == .restore(Self.small))
        // Restored, it fills again next time.
        #expect(memory.step(for: 1, frame: Self.small, usable: Self.usable, toggle: true) == .fill(Self.usable))
    }

    @Test("A window that fills the area with nothing remembered stays put")
    func nothingRemembered() {
        var memory = MaximizeMemory<Int>()
        #expect(memory.step(for: 1, frame: Self.usable, usable: Self.usable, toggle: true) == .stay)
    }

    @Test("Without toggle, a maximized window stays maximized")
    func noToggle() {
        var memory = MaximizeMemory<Int>()
        memory.record(1, before: Self.small, after: Self.usable)
        #expect(memory.step(for: 1, frame: Self.usable, usable: Self.usable, toggle: false) == .stay)
    }

    @Test("The memory is per window")
    func perWindow() {
        var memory = MaximizeMemory<Int>()
        memory.record(1, before: Self.small, after: Self.usable)
        #expect(memory.step(for: 2, frame: Self.usable, usable: Self.usable, toggle: true) == .stay)
        #expect(memory.step(for: 1, frame: Self.usable, usable: Self.usable, toggle: true) == .restore(Self.small))
    }

    @Test("A window that moved since Maximize forgets its old frame")
    func moved() {
        var memory = MaximizeMemory<Int>()
        memory.record(1, before: Self.small, after: Self.usable)
        let moved = CGRect(x: 300, y: 200, width: 700, height: 500)
        #expect(memory.step(for: 1, frame: moved, usable: Self.usable, toggle: true) == .fill(Self.usable))
        #expect(memory.step(for: 1, frame: Self.usable, usable: Self.usable, toggle: true) == .stay)
    }

    @Test("An app that snaps its size short of the area still restores")
    func snapped() {
        var memory = MaximizeMemory<Int>()
        let snapped = CGRect(x: 0, y: 33, width: 1505, height: 940)
        memory.record(1, before: Self.small, after: snapped)
        #expect(memory.step(for: 1, frame: snapped, usable: Self.usable, toggle: true) == .restore(Self.small))
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let toggled = try ActionRegistryTests.decode(#"{ "type": "window.maximize" }"#)
        #expect(toggled == .family(AnyActionValue(MaximizeAction(toggle: true))))
        let fill = try ActionRegistryTests.decode(#"{ "type": "window.maximize", "toggle": false }"#)
        #expect(ConfigWriter.action(fill, contexts: []) == #"{ "type": "window.maximize", "toggle": false }"#)
        #expect(ConfigWriter.action(toggled, contexts: []) == #"{ "type": "window.maximize" }"#)
        #expect(try ActionPlanner.plan(fill, home: testHome) == .custom(AnyActionStep(WindowCommand.maximize(toggle: false))))
        #expect(toggled.displayName == "Maximize")
    }
}

@Suite("Minimize (S-063)")
struct MinimizeTests {
    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let action = try ActionRegistryTests.decode(#"{ "type": "window.minimize" }"#)
        #expect(action == .family(AnyActionValue(MinimizeAction())))
        #expect(ConfigWriter.action(action, contexts: []) == #"{ "type": "window.minimize" }"#)
        #expect(try ActionPlanner.plan(action, home: testHome) == .custom(AnyActionStep(WindowCommand.minimize)))
        #expect(throws: (any Error).self) { try ActionRegistryTests.decode(#"{ "type": "window.minimize", "toggle": true }"#) }
    }
}
