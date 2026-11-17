import CoreGraphics
import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Focus and swap only the windows you can see, in reading order (S-082, spec v12)")
struct SeenWindowTests {
    static let screens = [
        WindowGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), usable: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
    ]

    /// Windows front to back, each with what the ones before it leave showing.
    static func stacked(_ frames: [CGRect]) -> [SeenWindow] {
        zip(frames, WindowGeometry.visibleParts(frames)).map { SeenWindow(frame: $0, parts: $1) }
    }

    static func order(_ windows: [SeenWindow], rowTolerance: Double = 20) -> [Int] {
        WindowGeometry.cycleOrder(windows, screens: screens, settings: Config.Windows(rowTolerance: rowTolerance))
    }

    @Test("A window's visible part is its frame minus the windows in front of it")
    func parts() {
        let front = CGRect(x: 0, y: 0, width: 960, height: 1080)
        let parts = WindowGeometry.visibleParts([front, front, CGRect(x: 480, y: 0, width: 960, height: 1080)])
        #expect(parts[0] == [front])
        #expect(parts[1].isEmpty)
        #expect(parts[2] == [CGRect(x: 960, y: 0, width: 480, height: 1080)])
    }

    @Test("A window counts when its visible part holds the square, even across parts")
    func square() {
        // A hole in the right of the window leaves three thin parts that hold a 50 point square together.
        let parts = WindowGeometry.visibleParts([CGRect(x: 50, y: 20, width: 100, height: 20), CGRect(x: 0, y: 0, width: 100, height: 60)])[1]
        #expect(parts.count == 3 && parts.allSatisfy { $0.width < 40 || $0.height < 40 })
        #expect(WindowGeometry.shows(parts, square: 40))
        #expect(WindowGeometry.shows(parts, square: 50))
        #expect(!WindowGeometry.shows(parts, square: 55))
    }

    @Test("A thin strip doesn't count, unless minVisible is 0; a hidden window never does")
    func strip() {
        let parts = WindowGeometry.visibleParts([CGRect(x: 0, y: 0, width: 490, height: 500), CGRect(x: 0, y: 0, width: 500, height: 500)])[1]
        #expect(!WindowGeometry.shows(parts, square: 20))
        #expect(WindowGeometry.shows(parts, square: 10))
        #expect(WindowGeometry.shows(parts, square: 0))
        #expect(!WindowGeometry.shows([], square: 0))
    }

    @Test("Down from the top half finds a quarter-width window below, whose center is far to the side")
    func wide() {
        let current = CGRect(x: 0, y: 0, width: 1920, height: 540)
        let below = [CGRect(x: 0, y: 540, width: 480, height: 540), CGRect(x: 1440, y: 540, width: 480, height: 540)]
        #expect(WindowGeometry.neighbor(of: current, .down, among: below.map { SeenWindow(frame: $0) }) == 0)
        #expect(WindowGeometry.neighbor(of: current, .down, among: [SeenWindow(frame: below[1])]) == 0)
    }

    @Test("From a window inside a larger one, every direction goes to the larger one")
    func enclosed() {
        let small = CGRect(x: 500, y: 300, width: 400, height: 300)
        let large = Self.stacked([small, CGRect(x: 0, y: 0, width: 1920, height: 1080)])[1]
        for direction in [FocusDirection.left, .right, .up, .down] {
            #expect(WindowGeometry.neighbor(of: small, direction, among: [large]) == 0)
        }
    }

    @Test("Only the part past the focused window's center counts")
    func pastCenter() {
        // A window behind the focused one, showing only on its left.
        let current = CGRect(x: 500, y: 0, width: 500, height: 500)
        let behind = Self.stacked([current, CGRect(x: 300, y: 0, width: 500, height: 500)])[1]
        #expect(WindowGeometry.neighbor(of: current, .right, among: [behind]) == nil)
        #expect(WindowGeometry.neighbor(of: current, .left, among: [behind]) == 0)
    }

    @Test("A window touching the side beats one further away; minVisible decides what's in line")
    func touching() {
        let current = CGRect(x: 0, y: 0, width: 500, height: 500)
        let beside = CGRect(x: 600, y: 0, width: 500, height: 500)
        let corner = CGRect(x: 500, y: 450, width: 300, height: 300)
        let windows = [beside, corner].map { SeenWindow(frame: $0) }
        #expect(WindowGeometry.neighbor(of: current, .right, among: windows) == 1)
        #expect(WindowGeometry.neighbor(of: current, .right, among: windows, settings: Config.Windows(minVisible: 60)) == 0)
    }

    @Test("Gaps within tieTolerance tie, and the window sharing more wins")
    func tie() {
        let current = CGRect(x: 0, y: 0, width: 500, height: 500)
        let near = CGRect(x: 500, y: 0, width: 300, height: 100)
        let level = CGRect(x: 501.5, y: 100, width: 300, height: 400)
        let windows = [near, level].map { SeenWindow(frame: $0) }
        #expect(WindowGeometry.neighbor(of: current, .right, among: windows) == 1)
        #expect(WindowGeometry.neighbor(of: current, .right, among: windows, settings: Config.Windows(tieTolerance: 0)) == 0)
    }

    @Test("A 3 by 2 grid reads across the top row first, so window 2 is the top middle")
    func grid() {
        let cells = (0..<6).map { CGRect(x: CGFloat($0 % 3) * 640, y: CGFloat($0 / 3) * 540, width: 640, height: 540) }
        let shuffled = [4, 0, 5, 2, 1, 3]
        let order = Self.order(shuffled.map { SeenWindow(frame: cells[$0]) }).map { shuffled[$0] }
        #expect(order == [0, 1, 2, 3, 4, 5])
    }

    @Test("A full-height window on the left and two stacked on the right read left, right top, right bottom")
    func mixed() {
        let left = CGRect(x: 0, y: 0, width: 960, height: 1080)
        let top = CGRect(x: 960, y: 0, width: 960, height: 540)
        let bottom = CGRect(x: 960, y: 540, width: 960, height: 540)
        #expect(Self.order([bottom, top, left].map { SeenWindow(frame: $0) }) == [2, 1, 0])
    }

    @Test("Tops within rowTolerance share a row")
    func rows() {
        let low = CGRect(x: 0, y: 10, width: 500, height: 500)
        let high = CGRect(x: 600, y: 0, width: 500, height: 500)
        let windows = [low, high].map { SeenWindow(frame: $0) }
        #expect(Self.order(windows) == [0, 1])
        #expect(Self.order(windows, rowTolerance: 5) == [1, 0])
    }

    @Test("A window's place in the order is the top left of what shows of it")
    func coveredTop() {
        let front = CGRect(x: 0, y: 0, width: 500, height: 200)
        let right = CGRect(x: 600, y: 100, width: 500, height: 500)
        let back = CGRect(x: 0, y: 0, width: 500, height: 500)
        #expect(Self.order(Self.stacked([front, right, back])) == [0, 1, 2])
    }

    @Test("The settings default to 20, 20 and 2, are written only when changed, and can't be negative")
    func settings() throws {
        let minimal = #"{ "version": 1, "entries": [ { "keys": "Meh+W", "title": "W" }, { "keys": "Meh+W H", "title": "H", "action": "h" } ], "actions": { "h": { "type": "noop" } }"#
        let plain = try ConfigLoader.load(Data((minimal + " }").utf8)).get()
        #expect(plain.config.windows == Config.Windows(minVisible: 20, rowTolerance: 20, tieTolerance: 2))
        #expect(!ConfigWriter.write(plain.config, actionOrder: []).contains("windows"))
        let set = #", "windows": { "minVisible": 40, "rowTolerance": 12.5, "tieTolerance": 0 } }"#
        let changed = try ConfigLoader.load(Data((minimal + set).utf8)).get()
        #expect(changed.config.windows == Config.Windows(minVisible: 40, rowTolerance: 12.5, tieTolerance: 0))
        #expect(ConfigWriter.write(changed.config, actionOrder: [])
                    .contains(#""windows": { "minVisible": 40, "rowTolerance": 12.5, "tieTolerance": 0 }"#))
        for name in ["minVisible", "rowTolerance", "tieTolerance"] {
            guard case let .failure(errors) = ConfigLoader.load(Data((minimal + #", "windows": { "\#(name)": -1 } }"#).utf8)) else {
                Issue.record("loaded a negative \(name)"); continue
            }
            #expect(errors.issues.first?.rule == .negativeWindowDistance)
        }
    }
}
