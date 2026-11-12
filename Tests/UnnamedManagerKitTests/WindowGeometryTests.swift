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

@Suite("Grow and shrink through widths (S-065)")
struct ResizeStepTests {
    static let usable = CGRect(x: 0, y: 25, width: 1200, height: 875)
    static let widths = ResizeAction.defaultWidths

    func step(_ frame: CGRect, _ step: ResizeStep, widths: [Double] = Self.widths) -> CGRect? {
        WindowGeometry.step(frame, in: Self.usable, widths: widths, step)
    }

    @Test("Grow picks the smallest width wider than the window, shrink the largest narrower")
    func next() {
        let window = CGRect(x: 100, y: 100, width: 500, height: 400)
        #expect(step(window, .grow)?.width == 600)
        #expect(step(window, .shrink)?.width == 400)
        // Within 2 points of a width counts as that width.
        #expect(step(CGRect(x: 100, y: 100, width: 599, height: 400), .grow)?.width == 800)
        #expect(step(window, .grow)?.height == 400)
    }

    @Test("Past the last width, the window stays put rather than wrapping")
    func ends() {
        #expect(step(CGRect(x: 0, y: 100, width: 900, height: 400), .grow) == nil)
        #expect(step(CGRect(x: 0, y: 100, width: 300, height: 400), .shrink) == nil)
    }

    @Test("It keeps the left edge, or the right edge when the left would push it off screen")
    func edges() {
        #expect(step(CGRect(x: 100, y: 100, width: 500, height: 400), .grow)?.minX == 100)
        let right = CGRect(x: 700, y: 100, width: 500, height: 400)
        #expect(step(right, .grow) == CGRect(x: 600, y: 100, width: 600, height: 400))
    }

    @Test("Order and duplicates in the widths don't matter")
    func unordered() {
        let window = CGRect(x: 0, y: 100, width: 500, height: 400)
        #expect(step(window, .grow, widths: [0.75, 0.25, 0.75, 0.5]) == step(window, .grow, widths: [0.25, 0.5, 0.75]))
    }

    @Test("It reads, writes and plans as the spec says, with the default widths when there are none")
    func family() throws {
        let grow = try ActionRegistryTests.decode(#"{ "type": "window.resize", "step": "grow" }"#)
        #expect(grow == .family(AnyActionValue(ResizeAction(.step(.grow, widths: nil)))))
        #expect(ConfigWriter.action(grow, contexts: []) == #"{ "type": "window.resize", "step": "grow" }"#)
        #expect(ResizeAction.defaultWidths == [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75])
        let json = #"{ "type": "window.resize", "step": "shrink", "widths": [0.75, 0.5, 0.25] }"#
        let shrink = try ActionRegistryTests.decode(json)
        #expect(ConfigWriter.action(shrink, contexts: []) == json)
        #expect(try ActionPlanner.plan(shrink, home: testHome)
                == .custom(AnyActionStep(WindowCommand.resize(.step(.shrink, widths: [0.75, 0.5, 0.25]), anchor: .topLeft))))
    }
}

@Suite("Move Window (S-066)")
struct MoveTests {
    static let usable = CGRect(x: 0, y: 25, width: 1440, height: 875)
    static let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test("to places the window at fractions of the free space")
    func to() {
        #expect(WindowGeometry.moved(Self.window, in: Self.usable, .to(x: 0, y: 0)) == CGRect(x: 0, y: 25, width: 800, height: 600))
        #expect(WindowGeometry.moved(Self.window, in: Self.usable, .to(x: 0.5, y: 0.5)) == CGRect(x: 320, y: 163, width: 800, height: 600))
        #expect(WindowGeometry.moved(Self.window, in: Self.usable, .to(x: 1, y: 1)) == CGRect(x: 640, y: 300, width: 800, height: 600))
        // Wider than the usable area: no free space, so the left edge.
        let wide = CGRect(x: 100, y: 100, width: 1600, height: 600)
        #expect(WindowGeometry.moved(wide, in: Self.usable, .to(x: 1, y: 0)).minX == 0)
    }

    @Test("by moves by points, and positive dy is down")
    func by() {
        #expect(WindowGeometry.moved(Self.window, in: Self.usable, .by(dx: 40, dy: 20)) == CGRect(x: 140, y: 120, width: 800, height: 600))
    }

    @Test("A move never takes the title bar off screen")
    func onScreen() {
        let left = WindowGeometry.moved(Self.window, in: Self.usable, .by(dx: -5000, dy: 0))
        #expect(left.maxX == 40)
        let right = WindowGeometry.moved(Self.window, in: Self.usable, .by(dx: 5000, dy: 0))
        #expect(right.minX == 1400)
        let down = WindowGeometry.moved(Self.window, in: Self.usable, .by(dx: 0, dy: 5000))
        #expect(down.minY == 860)
        let up = WindowGeometry.moved(Self.window, in: Self.usable, .by(dx: 0, dy: -5000))
        #expect(up.minY == 25)
        #expect(left.size == Self.window.size && down.size == Self.window.size)
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let json = #"{ "type": "window.move", "to": { "x": 0.5, "y": 0.5 } }"#
        let center = try ActionRegistryTests.decode(json)
        #expect(ConfigWriter.action(center, contexts: []) == json)
        let nudge = try ActionRegistryTests.decode(#"{ "type": "window.move", "by": { "dx": 0, "dy": -40 } }"#)
        #expect(ConfigWriter.action(nudge, contexts: []) == #"{ "type": "window.move", "by": { "dy": -40 } }"#)
        #expect(try ActionPlanner.plan(nudge, home: testHome) == .custom(AnyActionStep(WindowCommand.move(.by(dx: 0, dy: -40)))))
    }
}

@Suite("Resize by a step or to a size (S-067)")
struct ResizeTests {
    static let usable = CGRect(x: 0, y: 25, width: 1440, height: 875)
    static let window = CGRect(x: 200, y: 200, width: 600, height: 400)

    func resize(_ change: ResizeAction.Change, _ anchor: Anchor = .topLeft, _ frame: CGRect = Self.window) -> CGRect {
        WindowGeometry.resized(frame, to: WindowGeometry.size(frame, in: Self.usable, change)!, keeping: anchor, in: Self.usable)
    }

    @Test("by changes the size by points; to sets it as fractions")
    func sizes() {
        #expect(resize(.by(dw: 100, dh: -50)).size == CGSize(width: 700, height: 350))
        #expect(resize(.to(width: 0.5, height: 0.5)).size == CGSize(width: 720, height: 438))
    }

    @Test("The anchor stays where it was; the default is the top left", arguments: Anchor.allCases)
    func anchor(_ anchor: Anchor) {
        let after = resize(.by(dw: 100, dh: 60), anchor)
        let (ax, ay) = anchor.unit
        #expect(after.minX + ax * after.width == Self.window.minX + ax * Self.window.width)
        #expect(after.minY + ay * after.height == Self.window.minY + ay * Self.window.height)
        #expect(ResizeAction(.by(dw: 1, dh: 1)).anchor == .topLeft)
    }

    @Test("The result is clamped to the usable area")
    func clamped() {
        let big = resize(.by(dw: 5000, dh: 5000))
        #expect(big == Self.usable)
        let nearEdge = CGRect(x: 1000, y: 600, width: 400, height: 280)
        let grown = resize(.by(dw: 200, dh: 100), .topLeft, nearEdge)
        #expect(Self.usable.contains(grown))
        #expect(grown.size == CGSize(width: 600, height: 380))
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let json = #"{ "type": "window.resize", "to": { "width": 0.5, "height": 0.5 }, "anchor": "center" }"#
        let half = try ActionRegistryTests.decode(json)
        #expect(ConfigWriter.action(half, contexts: []) == json)
        let taller = try ActionRegistryTests.decode(#"{ "type": "window.resize", "by": { "dh": 100 } }"#)
        #expect(ConfigWriter.action(taller, contexts: []) == #"{ "type": "window.resize", "by": { "dh": 100 } }"#)
        #expect(try ActionPlanner.plan(taller, home: testHome)
                == .custom(AnyActionStep(WindowCommand.resize(.by(dw: 0, dh: 100), anchor: .topLeft))))
    }
}

@Suite("Focus a window by direction (S-068)")
struct FocusDirectionTests {
    static let current = CGRect(x: 600, y: 400, width: 400, height: 300)

    @Test("The nearest center within 45° of the direction wins")
    func nearest() {
        let near = CGRect(x: 1100, y: 420, width: 300, height: 300)
        let far = CGRect(x: 1600, y: 400, width: 300, height: 300)
        #expect(WindowGeometry.neighbor(of: Self.current, .right, among: [far, near]) == 1)
    }

    @Test("A window outside the 45° cone isn't that way")
    func cone() {
        let steep = CGRect(x: 1100, y: 1200, width: 300, height: 300)
        #expect(WindowGeometry.neighbor(of: Self.current, .right, among: [steep]) == nil)
        #expect(WindowGeometry.neighbor(of: Self.current, .down, among: [steep]) == 0)
    }

    @Test("A tie goes to the window that overlaps more on the other axis")
    func tie() {
        // Both centers are 500 points away; the second lines up exactly.
        let offset = CGRect(x: 1000, y: 100, width: 400, height: 300)
        let aligned = CGRect(x: 1100, y: 400, width: 400, height: 300)
        let a = hypot(offset.midX - Self.current.midX, offset.midY - Self.current.midY)
        let b = hypot(aligned.midX - Self.current.midX, aligned.midY - Self.current.midY)
        #expect(abs(a - b) < 0.5)
        #expect(WindowGeometry.neighbor(of: Self.current, .right, among: [offset, aligned]) == 1)
    }

    @Test("Each direction looks its own way, up being smaller y")
    func directions() {
        let left = CGRect(x: 0, y: 400, width: 300, height: 300)
        let above = CGRect(x: 600, y: 0, width: 400, height: 300)
        let windows = [left, above]
        #expect(WindowGeometry.neighbor(of: Self.current, .left, among: windows) == 0)
        #expect(WindowGeometry.neighbor(of: Self.current, .up, among: windows) == 1)
        #expect(WindowGeometry.neighbor(of: Self.current, .down, among: windows) == nil)
    }

    @Test("With no window that way, it says which way")
    func failures() {
        #expect(WindowCommand.focus(.left).failure == "No window to the left.")
        #expect(WindowCommand.focus(.right).failure == "No window to the right.")
        #expect(WindowCommand.focus(.up).failure == "No window above.")
        #expect(WindowCommand.focus(.down).failure == "No window below.")
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let json = #"{ "type": "window.focus", "direction": "left" }"#
        let left = try ActionRegistryTests.decode(json)
        #expect(ConfigWriter.action(left, contexts: []) == json)
        #expect(try ActionPlanner.plan(left, home: testHome) == .custom(AnyActionStep(WindowCommand.focus(.left))))
    }
}
