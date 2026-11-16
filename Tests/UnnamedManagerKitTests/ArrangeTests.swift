import CoreGraphics
import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Arrange Windows (S-075, S-076, spec v8)")
struct ArrangeTests {
    static let wide = CGRect(x: 0, y: 25, width: 1440, height: 875)
    static let tall = CGRect(x: 0, y: 0, width: 1080, height: 1920)
    static let small = CGRect(x: 100, y: 100, width: 800, height: 600)

    /// The frame each window gets, without the gap, by its index; nil for a window left alone.
    func arranged(_ action: ArrangeAction, maxColumns: Int = 2, maxRows: Int = 2,
                  usable: CGRect = ArrangeTests.wide, _ windows: [CGRect]) -> [CGRect?] {
        let plan = ArrangeGrid.plan(action, maxColumns: maxColumns, maxRows: maxRows, usable: usable, windows: windows)
        return windows.indices.map { index in plan.first { $0.window == index }?.cell.rect(in: usable) }
    }

    /// The same for the plain action: the two windows used last.
    func arranged(_ windows: [CGRect]) -> [CGRect?] {
        arranged(ArrangeAction(), windows)
    }

    static let left = CGRect(x: 0, y: 25, width: 720, height: 875), right = CGRect(x: 720, y: 25, width: 720, height: 875)
    static let topLeft = CGRect(x: 0, y: 25, width: 720, height: 438), bottomLeft = CGRect(x: 0, y: 463, width: 720, height: 437)

    @Test("Two windows keep their order: the leftmost goes left, whichever has focus")
    func halves() {
        let a = CGRect(x: 50, y: 100, width: 600, height: 500), b = CGRect(x: 500, y: 200, width: 600, height: 500)
        #expect(arranged([a, b]) == [Self.left, Self.right])
        #expect(arranged([b, a]) == [Self.right, Self.left])
    }

    @Test("Windows in the same spot go by use, the focused one on the right, or at the top")
    func tie() {
        #expect(arranged([Self.small, Self.small]) == [Self.right, Self.left])
        #expect(arranged(ArrangeAction(layout: .rows), [Self.small, Self.small])
                == [CGRect(x: 0, y: 25, width: 1440, height: 438), CGRect(x: 0, y: 463, width: 1440, height: 437)])
    }

    @Test("Arranged windows stay where they are when the action runs again")
    func repeated() {
        #expect(arranged([Self.right, Self.left]) == [Self.right, Self.left])
        #expect(arranged([Self.left, Self.right]) == [Self.left, Self.right])
        let thirds = arranged(ArrangeAction(count: .windows(3)), [Self.right, Self.bottomLeft, Self.topLeft])
        #expect(thirds == [Self.right, Self.bottomLeft, Self.topLeft])
    }

    @Test("Three windows in two columns: the focused one takes the whole column on its side, the others keep their order")
    func uneven() {
        let focused = CGRect(x: 0, y: 30, width: 400, height: 300)
        let upper = CGRect(x: 600, y: 40, width: 400, height: 300), lower = CGRect(x: 300, y: 500, width: 400, height: 300)
        let topRight = CGRect(x: 720, y: 25, width: 720, height: 438), bottomRight = CGRect(x: 720, y: 463, width: 720, height: 437)
        #expect(arranged(ArrangeAction(count: .windows(3)), [focused, lower, upper]) == [Self.left, bottomRight, topRight])
        // Focusing another window and running it again gives that one its column, on its side.
        #expect(arranged(ArrangeAction(count: .windows(3)), [topRight, Self.left, bottomRight])
                == [Self.right, Self.topLeft, Self.bottomLeft])
    }

    /// Five windows spread from left to right, the focused one at `place`, and where each ends in three columns.
    func five(focusedAt place: Int) -> [CGRect?] {
        var windows = (0..<5).map { CGRect(x: 100 + 200 * CGFloat($0), y: 100 + 50 * CGFloat($0), width: 400, height: 300) }
        windows.insert(windows.remove(at: place), at: 0)
        var frames = arranged(ArrangeAction(count: .windows(5)), maxColumns: 3, windows)
        frames.insert(frames.remove(at: 0), at: place)
        return frames
    }

    @Test("Five windows in three columns: the focused one fills the column it's in, top to bottom")
    func spare() {
        func cell(_ column: CGFloat, _ row: Int?) -> CGRect {
            switch row {
            case 0: CGRect(x: 480 * column, y: 25, width: 480, height: 438)
            case 1: CGRect(x: 480 * column, y: 463, width: 480, height: 437)
            default: CGRect(x: 480 * column, y: 25, width: 480, height: 875)
            }
        }
        #expect(five(focusedAt: 4) == [cell(0, 0), cell(0, 1), cell(1, 0), cell(1, 1), cell(2, nil)])
        #expect(five(focusedAt: 2) == [cell(0, 0), cell(0, 1), cell(1, nil), cell(2, 0), cell(2, 1)])
        #expect(five(focusedAt: 0) == [cell(0, nil), cell(1, 0), cell(1, 1), cell(2, 0), cell(2, 1)])
    }

    @Test("Eight windows in three columns: the focused one takes the spare cell next to it, and its neighbour keeps a third")
    func shared() {
        let windows = [CGRect(x: 900, y: 500, width: 400, height: 300), CGRect(x: 900, y: 40, width: 400, height: 300)]
            + (0..<6).map { CGRect(x: 50 * CGFloat($0), y: 100, width: 400, height: 300) }
        let frames = arranged(ArrangeAction(count: .windows(8), groups: 3), windows)
        #expect(frames[1] == CGRect(x: 960, y: 25, width: 480, height: 292) && frames[0] == CGRect(x: 960, y: 317, width: 480, height: 583))
        #expect(frames.dropFirst(2).allSatisfy { $0?.height == 292 || $0?.height == 291 })
    }

    @Test("Four windows in three columns: the focused one fills its column, and the last column has one window too")
    func leftover() {
        let windows = [1, 0, 2, 3].map { CGRect(x: 100 + 200 * CGFloat($0), y: 100, width: 400, height: 300) }
        let frames = arranged(ArrangeAction(count: .windows(4), groups: 3), windows)
        #expect(frames == [CGRect(x: 480, y: 25, width: 480, height: 875), CGRect(x: 0, y: 25, width: 480, height: 438),
                           CGRect(x: 0, y: 463, width: 480, height: 437), CGRect(x: 960, y: 25, width: 480, height: 875)])
    }

    @Test("With groups, three windows are three equal columns")
    func thirds() {
        let frames = arranged(ArrangeAction(count: .windows(3), groups: 3), [Self.small, Self.small, Self.small])
        #expect(frames == [CGRect(x: 960, y: 25, width: 480, height: 875), CGRect(x: 480, y: 25, width: 480, height: 875),
                           CGRect(x: 0, y: 25, width: 480, height: 875)])
    }

    @Test("Fewer windows than cells leave the cells on the left and at the bottom empty")
    func blanks() {
        #expect(arranged([Self.small]) == [Self.right])
        #expect(arranged(ArrangeAction(count: .windows(3), groups: 3), [Self.small, Self.small])
                == [CGRect(x: 960, y: 25, width: 480, height: 875), CGRect(x: 480, y: 25, width: 480, height: 875)])
        // Two windows for three cells in two columns: the focused one's column, and the top of the other.
        #expect(arranged(ArrangeAction(count: .windows(3)), [Self.small, Self.small])
                == [Self.left, CGRect(x: 720, y: 25, width: 720, height: 438)])
    }

    @Test("Windows past the count are left alone")
    func extra() {
        #expect(arranged([Self.small, Self.small, Self.small])[2] == nil)
    }

    @Test("All arranges every window up to the settings' limit, in columns up to the maximum")
    func all() {
        let windows = Array(repeating: Self.small, count: 6)
        let four = arranged(ArrangeAction(count: .all), windows)
        #expect(four.compactMap { $0 }.count == 4 && four[4] == nil && four[5] == nil)
        #expect(Set(four.compactMap { $0 }.map(\.width)) == [720] && four[0] == CGRect(x: 720, y: 25, width: 720, height: 438))
        #expect(arranged(ArrangeAction(count: .all), [Self.small]) == [Self.wide])
        #expect(arranged(ArrangeAction(count: .all), Array(windows.prefix(3)))
                == [Self.left, CGRect(x: 720, y: 25, width: 720, height: 438), CGRect(x: 720, y: 463, width: 720, height: 437)])
        // Wider settings: three equal columns, and never more than 8 windows.
        #expect(arranged(ArrangeAction(count: .all), maxColumns: 4, Array(windows.prefix(3))).compactMap { $0?.width } == [480, 480, 480])
        #expect(arranged(ArrangeAction(count: .all), maxColumns: 8, maxRows: 8, Array(repeating: Self.small, count: 10))
            .compactMap { $0 }.count == 8)
    }

    @Test("An automatic layout is rows on a tall display, and the focused window fills the row it's in")
    func rows() {
        let frames = arranged(ArrangeAction(count: .windows(3)), usable: Self.tall, [Self.small, Self.small, Self.small])
        #expect(frames == [CGRect(x: 0, y: 0, width: 1080, height: 960), CGRect(x: 540, y: 960, width: 540, height: 960),
                           CGRect(x: 0, y: 960, width: 540, height: 960)])
        #expect(arranged(ArrangeAction(layout: .columns), usable: Self.tall, [Self.small, Self.small])[0]
                == CGRect(x: 540, y: 0, width: 540, height: 1920))
    }

    @Test("Any grid fills the usable area, gives the focused window the most room, and stays when run again",
          arguments: [1440.0, 1512, 1727, 3440, 1001])
    func grids(_ width: Double) {
        let usable = CGRect(x: 0, y: 0, width: width, height: 901)
        for count in 2...8 {
            for groups in 1...count {
                for layout in [ArrangeLayout.columns, .rows] {
                    let action = ArrangeAction(count: .windows(count), groups: groups, layout: layout)
                    let start = arranged(action, usable: usable, Array(repeating: Self.small, count: count)).compactMap { $0 }
                    // Each window in turn has the focus.
                    for focused in 0..<count {
                        var windows = start
                        windows.insert(windows.remove(at: focused), at: 0)
                        let cells = arranged(action, usable: usable, windows).compactMap { $0 }
                        let areas = cells.map { $0.width * $0.height }
                        #expect(cells.count == count && areas.reduce(0, +) == CGFloat(width * 901))
                        #expect(areas[0] >= areas.max()! - CGFloat(max(width, 901)), "\(count) in \(groups), \(layout)")
                        for cell in cells { #expect(cell.intersection(usable) == cell) }
                        #expect(arranged(action, usable: usable, cells) == cells, "\(count) in \(groups), \(layout), focus \(focused)")
                        // With one window gone, the others stay too.
                        let fewer = Array(cells.dropLast())
                        let once = arranged(action, usable: usable, fewer).compactMap { $0 }
                        #expect(arranged(action, usable: usable, once) == once, "\(count - 1) of \(count) in \(groups), \(layout)")
                    }
                }
            }
        }
    }

    @Test("It reads, writes and plans as the spec says")
    func family() throws {
        let plain = try ActionRegistryTests.decode(#"{ "type": "window.arrange" }"#)
        #expect(plain == .family(AnyActionValue(ArrangeAction())))
        #expect(ConfigWriter.action(plain, contexts: []) == #"{ "type": "window.arrange" }"#)
        #expect(plain.displayName == "Arrange Windows")
        let full = #"{ "type": "window.arrange", "count": "all", "groups": 3, "layout": "rows" }"#
        let all = try ActionRegistryTests.decode(full)
        #expect(all == .family(AnyActionValue(ArrangeAction(count: .all, groups: 3, layout: .rows))))
        #expect(ConfigWriter.action(all, contexts: []) == full)
        let three = try ActionRegistryTests.decode(#"{ "type": "window.arrange", "count": 3 }"#)
        #expect(ConfigWriter.action(three, contexts: []) == #"{ "type": "window.arrange", "count": 3 }"#)
        #expect(try ActionPlanner.plan(three, home: testHome)
                == .custom(AnyActionStep(WindowCommand.arrange(ArrangeAction(count: .windows(3))))))
    }

    @Test("The two limits are read, checked and written only when they aren't the defaults")
    func limits() throws {
        let json = #"{ "version": 1, "windows": { "maxColumns": 3 }, "entries": [{ "keys": "Meh+A", "title": "A", "action": "a" }], "actions": { "a": { "type": "window.arrange" } } }"#
        let document = try ConfigDocument(data: Data(json.utf8))
        #expect(document.config.windows == Config.Windows(maxColumns: 3))
        #expect(String(decoding: document.data(), as: UTF8.self).contains(#""windows": { "maxColumns": 3 }"#))
    }
}
