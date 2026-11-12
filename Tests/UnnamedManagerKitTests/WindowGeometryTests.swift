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

@Suite("Place Window (S-064)")
struct PlaceTests {
    static let screens: [CGRect] = [
        CGRect(x: 0, y: 33, width: 1512, height: 949),
        CGRect(x: 1512, y: -175, width: 2560, height: 1415),
        CGRect(x: -1081, y: 0, width: 1081, height: 1895),
        CGRect(x: 0, y: 25, width: 1513, height: 875),
    ]

    @Test("Presets map to the expected frames")
    func presets() {
        let usable = CGRect(x: 0, y: 33, width: 1512, height: 949)
        #expect(WindowGeometry.rect(PlacePreset.leftHalf.frame, in: usable) == CGRect(x: 0, y: 33, width: 756, height: 949))
        #expect(WindowGeometry.rect(PlacePreset.rightThird.frame, in: usable) == CGRect(x: 1008, y: 33, width: 504, height: 949))
        #expect(WindowGeometry.rect(PlacePreset.bottomRight.frame, in: usable) == CGRect(x: 756, y: 508, width: 756, height: 475 - 1))
        #expect(WindowGeometry.rect(PlacePreset.center.frame, in: usable) == CGRect(x: 252, y: 191, width: 1008, height: 633))
        let wide = CGRect(x: 1512, y: -175, width: 2560, height: 1415)
        #expect(WindowGeometry.rect(PlacePreset.rightHalf.frame, in: wide) == CGRect(x: 2792, y: -175, width: 1280, height: 1415))
    }

    @Test("Neighbouring presets share an edge, with no gap or overlap, on every screen", arguments: screens)
    func neighbours(_ usable: CGRect) {
        func rect(_ preset: PlacePreset) -> CGRect { WindowGeometry.rect(preset.frame, in: usable) }
        #expect(rect(.leftHalf).maxX == rect(.rightHalf).minX)
        #expect(rect(.topHalf).maxY == rect(.bottomHalf).minY)
        #expect(rect(.leftThird).maxX == rect(.centerThird).minX)
        #expect(rect(.centerThird).maxX == rect(.rightThird).minX)
        #expect(rect(.leftThird).maxX == rect(.rightTwoThirds).minX)
        #expect(rect(.leftTwoThirds).maxX == rect(.rightThird).minX)
        #expect(rect(.topLeft).maxX == rect(.topRight).minX && rect(.topLeft).maxY == rect(.bottomLeft).minY)
        #expect(rect(.rightHalf).maxX == usable.maxX && rect(.bottomHalf).maxY == usable.maxY)
        for preset in PlacePreset.allCases {
            let frame = rect(preset)
            #expect(frame == frame.integral, "\(preset) isn't on whole points: \(frame)")
            #expect(usable.contains(frame), "\(preset) runs past the usable area")
        }
    }

    @Test("Cocoa rects flip for displays left and right of the main one")
    func flipSideways() {
        #expect(WindowGeometry.topLeft(CGRect(x: -1081, y: -913, width: 1081, height: 1895), primaryHeight: 982)
                == CGRect(x: -1081, y: 0, width: 1081, height: 1895))
        #expect(WindowGeometry.topLeft(CGRect(x: 1512, y: -258, width: 2560, height: 1440), primaryHeight: 982)
                == CGRect(x: 1512, y: -200, width: 2560, height: 1440))
    }

    @Test("A window that won't take the size keeps the edge it was placed against")
    func anchored() {
        let usable = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let right = WindowGeometry.rect(PlacePreset.rightHalf.frame, in: usable)
        #expect(WindowGeometry.anchored(CGSize(width: 900, height: 875), to: right, in: usable)
                == CGRect(x: 540, y: 25, width: 900, height: 875))
        let left = WindowGeometry.rect(PlacePreset.leftHalf.frame, in: usable)
        #expect(WindowGeometry.anchored(CGSize(width: 900, height: 875), to: left, in: usable).minX == 0)
        let center = WindowGeometry.rect(PlacePreset.center.frame, in: usable)
        #expect(WindowGeometry.anchored(CGSize(width: 1000, height: 700), to: center, in: usable).midX == center.midX)
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let preset = try ActionRegistryTests.decode(#"{ "type": "window.place", "preset": "rightThird" }"#)
        #expect(ConfigWriter.action(preset, contexts: []) == #"{ "type": "window.place", "preset": "rightThird" }"#)
        #expect(try ActionPlanner.plan(preset, home: testHome) == .custom(AnyActionStep(WindowCommand.place(PlacePreset.rightThird.frame))))
        let json = #"{ "type": "window.place", "frame": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.9 } }"#
        let frame = try ActionRegistryTests.decode(json)
        #expect(ConfigWriter.action(frame, contexts: []) == json)
        // Thirds written out to four places still add up to 1.
        #expect(throws: Never.self) {
            try ActionRegistryTests.decode(#"{ "type": "window.place", "frame": { "x": 0.6667, "y": 0, "width": 0.3334, "height": 1 } }"#)
        }
    }

    @Test("A frame with a field it doesn't have is an unknown field")
    func unknownInFrame() {
        let json = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W", "action": "p" } ], "actions": { "p": { "type": "window.place", "frame": { "x": 0, "y": 0, "width": 1, "height": 1, "z": 1 } } } }"#
        guard case let .failure(errors) = ConfigLoader.load(Data(json.utf8)) else { Issue.record("loaded"); return }
        #expect(errors.issues.first?.rule == .unknownField)
        #expect(errors.issues.first?.message.contains("“z”") == true)
    }
}
