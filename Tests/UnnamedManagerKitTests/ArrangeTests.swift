import CoreGraphics
import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Arrange Windows (S-075, S-076, spec v8 and v9)")
struct ArrangeTests {
    static let wide = CGRect(x: 0, y: 25, width: 1440, height: 875)
    static let tall = CGRect(x: 0, y: 0, width: 1080, height: 1920)
    static let small = CGRect(x: 100, y: 100, width: 800, height: 600)

    /// The frame each window gets, without the gap, by its index; nil for a window left alone.
    /// `minCell` is 6 by 6 steps by default, which on these 12 by 12 step displays allows 2 by 2.
    func arranged(_ action: ArrangeAction, minCell: WindowSteps = Config.Windows.standardMinCell, steps: WindowSteps? = nil,
                  usable: CGRect = ArrangeTests.wide, minimums: [CGSize] = [], _ windows: [CGRect]) -> [CGRect?] {
        let plan = ArrangeGrid.plan(action, steps: steps ?? WindowSteps.guess(for: usable.size), minCell: minCell, usable: usable,
                                    windows: windows, minimums: minimums)
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
        var frames = arranged(ArrangeAction(count: .windows(5)), minCell: .init(across: 4, down: 6), windows)
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
        // A smaller cell: three equal columns, and past 8 windows (spec v24).
        #expect(arranged(ArrangeAction(count: .all), minCell: .init(across: 3, down: 6), Array(windows.prefix(3))).compactMap { $0?.width } == [480, 480, 480])
        #expect(arranged(ArrangeAction(count: .all), minCell: .init(across: 3, down: 3), Array(repeating: Self.small, count: 20))
            .compactMap { $0 }.count == 16)
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
                        // On steps, the leftover steps go from the left or top, so the focused window may get one step less.
                        let step = CGFloat(width * 901 / 12 * 2) + 1
                        #expect(areas[0] >= areas.max()! - step, "\(count) in \(groups), \(layout)")
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

    @Test("The retired limits load with a warning and are dropped when the file is saved (spec v24)")
    func retired() throws {
        let json = #"{ "version": 1, "windows": { "maxColumns": 3 }, "entries": [{ "keys": "Meh+A", "title": "A", "action": "a" }], "actions": { "a": { "type": "window.arrange" } } }"#
        let document = try ConfigDocument(data: Data(json.utf8))
        #expect(document.config.windows == Config.Windows(maxColumns: 3))
        let loaded = try ConfigLoader.load(Data(json.utf8)).get()
        #expect(loaded.warnings.map(\.rule) == [.retiredSetting] && loaded.warnings.first?.subject == "maxColumns")
        #expect(!String(decoding: document.data(), as: UTF8.self).contains("windows"))
    }

    @Test("minCell, displays and each app's smallest size read and write, defaults left out (spec v24)")
    func settings() throws {
        let windows = #""windows": { "minCell": { "across": 4, "down": 6 }, "displays": { "3840x1080": { "steps": { "across": 36, "down": 12 } } }, "apps": { "com.example.Editor": { "focus": true, "swap": true, "arrange": true, "quit": true, "minWidth": 1600 } } }"#
        let json = [#"{ "version": 1, "#, windows, #", "entries": [{ "keys": "Meh+A", "title": "A", "action": "window-tidy" }] }"#].joined()
        let document = try ConfigDocument(data: Data(json.utf8))
        #expect(document.config.windows.minCell == .init(across: 4, down: 6))
        #expect(document.config.windows.apps["com.example.Editor"]?.minWidth == 1600)
        #expect(String(decoding: document.data(), as: UTF8.self).contains(windows))
    }

    @Test("Steps come from the display's settings or the guess, and minCell sets the limits (spec v24)")
    func limits() {
        var settings = Config.Windows(displays: ["3840x1080": .init(minCell: .init(across: 4, down: 6))])
        let wide = CGSize(width: 3840, height: 1080), laptop = CGSize(width: 1512, height: 982)
        #expect(settings.steps(for: wide) == .init(across: 36, down: 12))
        #expect(settings.limits(for: wide) == (9, 2))
        #expect(settings.limits(for: laptop) == (2, 2))
        #expect(settings.limits(for: CGSize(width: 3440, height: 1440)) == (4, 2))
        settings.displays["1512x982"] = .init(steps: .init(across: 24, down: 12))
        #expect(settings.limits(for: laptop) == (4, 2))
        // A smallest cell larger than the steps counts as all of them.
        settings.minCell = .init(across: 96, down: 96)
        #expect(settings.limits(for: CGSize(width: 1920, height: 1080)) == (1, 1))
    }

    @Test("Cells land on steps, the leftover steps one each from the left (spec v24)")
    func onSteps() {
        // 1001 points in 12 steps: 7 columns get 2, 2, 2, 2, 2, 1, 1 steps.
        let usable = CGRect(x: 0, y: 0, width: 1001, height: 900)
        let frames = arranged(ArrangeAction(count: .windows(7), groups: 7), minCell: .init(across: 1, down: 1), usable: usable,
                              (0..<7).map { CGRect(x: 100 * CGFloat($0), y: 0, width: 200, height: 200) }).compactMap { $0 }
        let edges = frames.map { Int($0.minX) }.sorted()
        #expect(edges == [0, 2, 4, 6, 8, 10, 11].map { Int((Double($0) / 12 * 1001).rounded()) }, "\(frames)")
        // Fewer steps than columns: equal columns.
        let few = arranged(ArrangeAction(count: .windows(3), groups: 3), steps: .init(across: 2, down: 1), usable: usable,
                           Array(repeating: Self.small, count: 3)).compactMap { $0?.width }
        #expect(few.allSatisfy { abs($0 - 1001.0 / 3) < 1 })
    }

    @Test("An app's smallest width takes room from the other columns, which keep minCell (spec v24)")
    func minimums() {
        let usable = CGRect(x: 0, y: 0, width: 3840, height: 1080)
        let windows = (0..<3).map { CGRect(x: 1000 * CGFloat($0), y: 0, width: 800, height: 800) }
        let cell = WindowSteps(across: 4, down: 6)
        // Plain: three columns of 12 steps each.
        #expect(arranged(ArrangeAction(count: .windows(3), groups: 3), minCell: cell, usable: usable, windows).map { $0?.width }
                == [1280, 1280, 1280])
        // The focused window needs 1600 points, 15 steps: the others share 21, 11 and 10.
        let wider = arranged(ArrangeAction(count: .windows(3), groups: 3), minCell: cell, usable: usable,
                             minimums: [CGSize(width: 1600, height: 0)], windows)
        #expect(wider[0]?.width == 1600 && wider[0]?.minX == 0)
        #expect(wider[1]?.minX == 1600 && wider[2]?.maxX == 3840)
        // 3000 points leaves less than minCell for the others: fewer columns.
        let fewer = arranged(ArrangeAction(count: .windows(3), groups: 3), minCell: cell, usable: usable,
                             minimums: [CGSize(width: 3000, height: 0)], windows)
        #expect(fewer[0]!.width >= 3000 && Set(fewer.compactMap { $0?.minX }).count == 2)
        // Wider than the display: the whole width.
        let whole = arranged(ArrangeAction(), minCell: cell, usable: usable, minimums: [CGSize(width: 5000, height: 0)],
                             Array(windows.prefix(2)))
        #expect(whole[0]?.width == 3840)
    }
    @Test("Settings writes a display's own steps and smallest cell, and leaves out the defaults (S-101)")
    func displaySettings() {
        var windows = Config.Windows()
        let wide = CGSize(width: 3840, height: 1080)
        windows.setSteps(WindowSteps(across: 48, down: 12), for: wide)
        #expect(windows.displays["3840x1080"] == Config.Windows.Display(steps: WindowSteps(across: 48, down: 12)))
        windows.setMinCell(WindowSteps(across: 4, down: 6), for: wide)
        #expect(windows.minCell(for: wide) == WindowSteps(across: 4, down: 6))
        // Back to the guess and the shared smallest cell: nothing of its own is left.
        windows.setSteps(WindowSteps(across: 36, down: 12), for: wide)
        #expect(windows.displays["3840x1080"]?.steps == nil)
        windows.setMinCell(Config.Windows.standardMinCell, for: wide)
        #expect(windows.displays.isEmpty)
        #expect(Config.Windows.size(ofDisplayKey: "3840x1080") == wide)
        #expect(Config.Windows.size(ofDisplayKey: "wide") == nil)
    }
}
