import Foundation
import UnnamedManagerKit

extension SelfTest {
    /// M11: window actions against `FakeWindowSystem`, through the same
    /// performer the app uses.
    static func windowChecks() async {
        let start = CGRect(x: 100, y: 100, width: 800, height: 600)
        let fake = FakeWindowSystem()
        fake.windows = ["notes": .init(frame: start)]
        fake.focused = "notes"
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { Config.Windows(gap: 0) }))))
        let fill = Config.Action.family(AnyActionValue(FillAction()))

        try? await runner.run(fill, id: "fill")
        check("S-062 Fill fills the usable area", fake.windows["notes"]?.frame == fake.displays[0].usable,
              "\(String(describing: fake.windows["notes"]?.frame))")
        try? await runner.run(fill, id: "fill")
        check("S-062 Fill again restores the first frame exactly", fake.windows["notes"]?.frame == start,
              "\(String(describing: fake.windows["notes"]?.frame))")

        fake.windows["capped"] = .init(frame: start, maxSize: CGSize(width: 1200, height: 800))
        fake.focused = "capped"
        try? await runner.run(fill, id: "fill")
        try? await runner.run(fill, id: "fill")
        check("S-062 a window with a maximum size still restores", fake.windows["capped"]?.frame == start,
              "\(String(describing: fake.windows["capped"]?.frame))")

        fake.focused = nil
        do throws(PlanError) {
            try await runner.run(fill, id: "fill")
            check("S-062 no focused window says so", false, "no failure")
        } catch {
            check("S-062 no focused window says so", error.message == "TextEdit has no window to fill.", error.message)
        }

        fake.focused = "notes"
        try? await runner.run(.family(AnyActionValue(MinimizeAction())), id: "minimize")
        check("S-063 Minimize sets the window minimized", fake.windows["notes"]?.isMinimized == true)
        fake.focused = nil
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(MinimizeAction())), id: "minimize")
            check("S-063 no focused window says so", false, "no failure")
        } catch {
            check("S-063 no focused window says so", error.message == "TextEdit has no window to minimize.", error.message)
        }

        fake.windows["wide"] = .init(frame: start, minSize: CGSize(width: 900, height: 300))
        fake.focused = "wide"
        try? await runner.run(.family(AnyActionValue(PlaceAction.preset(.rightHalf))), id: "right")
        check("S-064 a window wider than the right half keeps the right edge",
              fake.windows["wide"]?.frame == CGRect(x: 540, y: 25, width: 900, height: 875),
              "\(String(describing: fake.windows["wide"]?.frame))")
        try? await runner.run(.family(AnyActionValue(PlaceAction.preset(.leftHalf))), id: "left")
        check("S-064 and the left half keeps the left edge",
              fake.windows["wide"]?.frame == CGRect(x: 0, y: 25, width: 900, height: 875),
              "\(String(describing: fake.windows["wide"]?.frame))")

        // Spec v3: the gap around placed windows, with a window too wide for its half.
        let gapped = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { Config.Windows(gap: 8) }))))
        fake.windows["gapped"] = .init(frame: start)
        fake.focused = "gapped"
        try? await gapped.run(.family(AnyActionValue(PlaceAction.preset(.leftHalf))), id: "left")
        let left = fake.windows["gapped"]?.frame
        try? await gapped.run(.family(AnyActionValue(PlaceAction.preset(.rightHalf))), id: "right")
        let right = fake.windows["gapped"]?.frame
        check("S-071 halves stand 8 points from the screen's edges and 8 points apart",
              left == CGRect(x: 8, y: 33, width: 708, height: 859) && right == CGRect(x: 724, y: 33, width: 708, height: 859),
              "\(String(describing: left)), \(String(describing: right))")
        fake.focused = "wide"
        try? await gapped.run(.family(AnyActionValue(PlaceAction.preset(.rightHalf))), id: "right")
        check("S-071 a window wider than its half keeps the right edge one gap in",
              fake.windows["wide"]?.frame.maxX == 1432, "\(String(describing: fake.windows["wide"]?.frame))")

        // Spec v7: Fill leaves the gap too, and the old name does the same.
        fake.windows["filled"] = .init(frame: start)
        fake.focused = "filled"
        try? await gapped.run(fill, id: "fill")
        check("S-074 Fill stands 8 points from every edge of the usable area",
              fake.windows["filled"]?.frame == CGRect(x: 8, y: 33, width: 1424, height: 859),
              "\(String(describing: fake.windows["filled"]?.frame))")
        let oldName = Config.Action.family(AnyActionValue(FillAction(type: FillAction.oldType)))
        try? await gapped.run(oldName, id: "maximize")
        check("S-074 pressed again, under its old name, it restores the first frame exactly",
              fake.windows["filled"]?.frame == start, "\(String(describing: fake.windows["filled"]?.frame))")

        fake.windows["narrow"] = .init(frame: CGRect(x: 100, y: 100, width: 300, height: 500))
        fake.focused = "narrow"
        let grow = Config.Action.family(AnyActionValue(ResizeAction(.step(.grow, widths: nil))))
        try? await runner.run(grow, id: "grow")
        try? await runner.run(grow, id: "grow")
        check("S-065 Grow twice goes from 300 to a third of 1440 points, keeping the left edge and height",
              fake.windows["narrow"]?.frame == CGRect(x: 100, y: 100, width: 480, height: 500),
              "\(String(describing: fake.windows["narrow"]?.frame))")

        fake.focused = "narrow"
        for move in [MoveAction.to(x: 0.5, y: 0.5), .by(dx: 40, dy: -40), .by(dx: -9000, dy: 9000)] {
            try? await runner.run(.family(AnyActionValue(move)), id: "move")
        }
        check("S-066 a window's size is unchanged after moves, and it stays on screen",
              fake.windows["narrow"]?.frame == CGRect(x: -440, y: 860, width: 480, height: 500),
              "\(String(describing: fake.windows["narrow"]?.frame))")

        fake.windows["dialog"] = .init(frame: start, isFixedSize: true)
        fake.focused = "dialog"
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(ResizeAction(.by(dw: 200, dh: 100), anchor: .center))), id: "bigger")
            check("S-067 a window with a fixed size reports no failure and stays as it was", fake.windows["dialog"]?.frame == start,
                  "\(String(describing: fake.windows["dialog"]?.frame))")
        } catch {
            check("S-067 a window with a fixed size reports no failure and stays as it was", false, error.message)
        }
        fake.focused = "notes"
        try? await runner.run(.family(AnyActionValue(ResizeAction(.to(width: 0.5, height: 0.5), anchor: .bottomRight))), id: "half")
        check("S-067 Resize to half keeps the bottom right corner", fake.windows["notes"]?.frame == CGRect(x: 180, y: 262, width: 720, height: 438),
              "\(String(describing: fake.windows["notes"]?.frame))")

        await focusChecks()
        await arrangeChecks()

        fake.canControlWindows = false
        do throws(PlanError) {
            try await runner.run(fill, id: "fill")
            check("S-062 without Accessibility, window actions say what to allow", false, "no failure")
        } catch {
            check("S-062 without Accessibility, window actions say what to allow",
                  error.message == "Unnamed Manager needs Accessibility access to move windows.", error.message)
        }
    }

    /// S-075, S-076: Arrange Windows on the first of two displays, with a gap of 8.
    static func arrangeChecks() async {
        let fake = FakeWindowSystem()
        fake.displays = [
            .init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), usable: CGRect(x: 0, y: 25, width: 1440, height: 875)),
            .init(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), usable: CGRect(x: 1440, y: 25, width: 1920, height: 1055)),
        ]
        let start = CGRect(x: 200, y: 100, width: 800, height: 600), away = CGRect(x: 1600, y: 100, width: 800, height: 600)
        fake.windows = ["editor": .init(frame: start), "browser": .init(frame: start), "notes": .init(frame: start), "away": .init(frame: away)]
        fake.stacking = ["editor", "away", "browser", "notes"]
        fake.focused = "editor"
        var settings = Config.Windows(gap: 8)
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { settings }))))
        func frame(_ id: String) -> CGRect? { fake.windows[id]?.frame }
        func run(_ action: ArrangeAction) async -> String? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "arrange")
                return nil
            } catch {
                return error.message
            }
        }
        let left = CGRect(x: 8, y: 33, width: 708, height: 859), right = CGRect(x: 724, y: 33, width: 708, height: 859)

        _ = await run(ArrangeAction())
        check("S-075 the two windows used last stand in halves, the focused one on the right, 8 points apart",
              frame("editor") == right && frame("browser") == left, "\(String(describing: frame("editor"))), \(String(describing: frame("browser")))")
        check("S-075 a third window, a window on another display and the focus stay as they were",
              frame("notes") == start && frame("away") == away && fake.focused == "editor")

        // The other window gets focus: nothing moves, since each is in its cell.
        fake.focused = "browser"
        fake.stacking = ["browser", "editor", "away", "notes"]
        _ = await run(ArrangeAction())
        check("S-075 run again from the other window, the halves stay", frame("editor") == right && frame("browser") == left)

        _ = await run(ArrangeAction(layout: .rows))
        check("S-075 with rows, the two are stacked, in the order they were in",
              frame("browser") == CGRect(x: 8, y: 33, width: 1424, height: 426) && frame("editor") == CGRect(x: 8, y: 467, width: 1424, height: 425),
              "\(String(describing: frame("browser"))), \(String(describing: frame("editor")))")

        _ = await run(ArrangeAction(count: .all))
        check("S-076 All gives the focused window the right half and stacks the two others on the left",
              frame("browser") == right && frame("editor") == CGRect(x: 8, y: 467, width: 708, height: 425)
                  && frame("notes") == CGRect(x: 8, y: 33, width: 708, height: 426) && frame("away") == away,
              "\(String(describing: frame("browser"))), \(String(describing: frame("editor"))), \(String(describing: frame("notes")))")

        settings.maxColumns = 3
        _ = await run(ArrangeAction(count: .all))
        check("S-076 with Maximum Columns at 3, the three are columns, 8 points apart",
              frame("browser") == CGRect(x: 964, y: 33, width: 468, height: 859) && frame("editor") == CGRect(x: 484, y: 33, width: 472, height: 859)
                  && frame("notes") == CGRect(x: 8, y: 33, width: 468, height: 859),
              "\(["browser", "editor", "notes"].map { String(describing: frame($0)) })")

        fake.focused = nil
        fake.app = nil
        fake.windows = ["editor": .init(frame: start), "browser": .init(frame: start)]
        fake.stacking = ["editor", "browser"]
        _ = await run(ArrangeAction())
        check("S-075 with no focused window, the one in front counts as focused", frame("editor") == right && frame("browser") == left)
        fake.windows = [:]
        let failure = await run(ArrangeAction())
        check("S-075 with no window at all, it says so", failure == "No window to arrange.", failure ?? "no failure")
    }

    /// S-068: four windows in a 2×2 grid across two displays side by side.
    static func focusChecks() async {
        let fake = FakeWindowSystem()
        fake.displays = [
            .init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), usable: CGRect(x: 0, y: 25, width: 1440, height: 875)),
            .init(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), usable: CGRect(x: 1440, y: 25, width: 1920, height: 1055)),
        ]
        fake.windows = [
            "a": .init(frame: CGRect(x: 100, y: 50, width: 1200, height: 380)),
            "b": .init(frame: CGRect(x: 1540, y: 50, width: 1600, height: 380)),
            "c": .init(frame: CGRect(x: 100, y: 480, width: 1200, height: 380)),
            "d": .init(frame: CGRect(x: 1540, y: 480, width: 1600, height: 380)),
        ]
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { Config.Windows(gap: 0) }))))
        let moves: [(String, FocusDirection, String)] = [
            ("a", .right, "b"), ("b", .down, "d"), ("d", .left, "c"), ("c", .up, "a"),
            ("b", .left, "a"), ("a", .down, "c"), ("c", .right, "d"), ("d", .up, "b"),
        ]
        var picks: [String] = []
        for (from, direction, _) in moves {
            fake.focused = from
            try? await runner.run(.family(AnyActionValue(FocusAction(direction))), id: "focus")
            picks.append(fake.focused ?? "none")
        }
        check("S-068 each direction picks the expected window across two displays", picks == moves.map(\.2), "\(picks)")
        fake.focused = "d"
        try? await runner.run(.family(AnyActionValue(FocusAction(.next))), id: "next")
        let wrapped = fake.focused
        try? await runner.run(.family(AnyActionValue(FocusAction(.previous))), id: "previous")
        check("S-069 Next from the last window goes to the first, and Previous goes back",
              wrapped == "a" && fake.focused == "d", "\(String(describing: wrapped)), \(String(describing: fake.focused))")

        // S-073: the order is a, c (left display), b, d; First and Last are its ends.
        var ends: [String] = []
        for (from, direction) in [("b", FocusDirection.first), ("c", .last), ("d", .last), (nil, .first), (nil, .last)] {
            fake.focused = from
            try? await runner.run(.family(AnyActionValue(FocusAction(direction))), id: "focus")
            ends.append(fake.focused ?? "none")
        }
        check("S-073 First and Last go to the leftmost and rightmost window, with or without a focused one",
              ends == ["a", "d", "d", "a", "d"], "\(ends)")

        fake.focused = "a"
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(FocusAction(.left))), id: "focus")
            check("S-068 no window that way says so", false, "no failure")
        } catch {
            check("S-068 no window that way says so", error.message == "No window to the left." && fake.focused == "a", error.message)
        }

        // S-072: with nothing focused, every direction goes to the window in front.
        fake.stacking = ["c", "b"]
        var tops: [String] = []
        for direction in [FocusDirection.left, .up, .next, .previous] {
            fake.focused = nil
            try? await runner.run(.family(AnyActionValue(FocusAction(direction))), id: "focus")
            tops.append(fake.focused ?? "none")
        }
        fake.app = nil
        fake.focused = nil
        try? await runner.run(.family(AnyActionValue(FocusAction(.right))), id: "focus")
        tops.append(fake.focused ?? "none")
        check("S-072 with no focused window, Focus Window goes to the window in front", tops == Array(repeating: "c", count: 5), "\(tops)")
        fake.windows = [:]
        fake.focused = nil
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(FocusAction(.next))), id: "focus")
            check("S-072 no window at all says so", false, "no failure")
        } catch {
            check("S-072 no window at all says so", error.message == "No window to focus.", error.message)
        }
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(FocusAction(.first))), id: "focus")
            check("S-073 First with no window at all says so", false, "no failure")
        } catch {
            check("S-073 First with no window at all says so", error.message == "No window to focus.", error.message)
        }
    }

    /// S-070: the window types in the Type picker, and each form's value
    /// saved as the spec writes it, then undone.
    static func windowEditingChecks(_ model: AppModel) async {
        let names = Config.Action.types(allowsContextAware: true).map { Config.Action.empty(of: $0).displayName }
        let window = ["Arrange Windows", "Fill", "Focus Window", "Minimize", "Move Window", "Place Window", "Resize Window"]
        check("S-070 the Type picker lists the window actions with the others, alphabetically",
              Set(window).isSubset(of: names) && names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(names)")
        check("S-074 the Type picker offers Fill once, and not under its old name",
              names.count { $0 == "Fill" } == 1 && !Config.Action.types(allowsContextAware: true).contains(FillAction.oldType), "\(names)")

        let editor = model.editor
        editor.reloadFromStore()
        let undo = UndoManager()
        undo.groupsByEvent = false
        func file() -> String { (try? String(contentsOf: model.store.url, encoding: .utf8)) ?? "" }
        let before = file()
        let cases: [(Config.Action, String)] = [
            (.family(AnyActionValue(ArrangeAction(count: .all, groups: 3, layout: .rows))),
             #"{ "type": "window.arrange", "count": "all", "groups": 3, "layout": "rows" }"#),
            (.family(AnyActionValue(FocusAction(.previous))), #"{ "type": "window.focus", "direction": "previous" }"#),
            (.family(AnyActionValue(FillAction(toggle: false))), #"{ "type": "window.fill", "toggle": false }"#),
            (.family(AnyActionValue(MinimizeAction())), #"{ "type": "window.minimize" }"#),
            (.family(AnyActionValue(MoveAction.by(dx: 40, dy: 0))), #"{ "type": "window.move", "by": { "dx": 40 } }"#),
            (.family(AnyActionValue(PlaceAction.frame(FractionFrame(x: 0.1, y: 0.05, width: 0.8, height: 0.9)))),
             #"{ "type": "window.place", "frame": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.9 } }"#),
            (.family(AnyActionValue(ResizeAction(.step(.shrink, widths: [0.75, 0.5, 0.25])))),
             #"{ "type": "window.resize", "step": "shrink", "widths": [0.75, 0.5, 0.25] }"#),
            (.family(AnyActionValue(ResizeAction(.by(dw: 80, dh: 60), anchor: .bottomRight))),
             #"{ "type": "window.resize", "by": { "dw": 80, "dh": 60 }, "anchor": "bottomRight" }"#),
        ]
        var written: [String] = []
        for (action, _) in cases {
            undo.beginUndoGrouping()
            editor.edit("Change Action", undo: undo) { $0.setAction(id: "window-test", action) }
            undo.endUndoGrouping()
            written.append(file().split(separator: "\n").first { $0.contains(#""window-test""#) }.map(String.init) ?? "")
        }
        let wrong = zip(written, cases).filter { !$0.0.contains($0.1.1) }.map(\.0)
        check("S-070 each window form saves the fields the spec defines", wrong.isEmpty, "\(wrong)")
        undo.beginUndoGrouping()
        editor.edit("Change Maximum Columns", undo: undo) { $0.config.windows.maxColumns = 3 }
        undo.endUndoGrouping()
        check("S-076 Maximum Columns is saved in the file's windows settings", file().contains(#""maxColumns": 3"#))
        while undo.canUndo { undo.undo() }
        check("S-070 Undo restores the file", file() == before)
    }
}
