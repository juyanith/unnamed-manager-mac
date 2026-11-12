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
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake))))
        let maximize = Config.Action.family(AnyActionValue(MaximizeAction()))

        try? await runner.run(maximize, id: "maximize")
        check("S-062 Maximize fills the usable area", fake.windows["notes"]?.frame == fake.displays[0].usable,
              "\(String(describing: fake.windows["notes"]?.frame))")
        try? await runner.run(maximize, id: "maximize")
        check("S-062 Maximize again restores the first frame exactly", fake.windows["notes"]?.frame == start,
              "\(String(describing: fake.windows["notes"]?.frame))")

        fake.windows["capped"] = .init(frame: start, maxSize: CGSize(width: 1200, height: 800))
        fake.focused = "capped"
        try? await runner.run(maximize, id: "maximize")
        try? await runner.run(maximize, id: "maximize")
        check("S-062 a window with a maximum size still restores", fake.windows["capped"]?.frame == start,
              "\(String(describing: fake.windows["capped"]?.frame))")

        fake.focused = nil
        do throws(PlanError) {
            try await runner.run(maximize, id: "maximize")
            check("S-062 no focused window says so", false, "no failure")
        } catch {
            check("S-062 no focused window says so", error.message == "TextEdit has no window to maximize.", error.message)
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

        fake.canControlWindows = false
        do throws(PlanError) {
            try await runner.run(maximize, id: "maximize")
            check("S-062 without Accessibility, window actions say what to allow", false, "no failure")
        } catch {
            check("S-062 without Accessibility, window actions say what to allow",
                  error.message == "Unnamed Manager needs Accessibility access to move windows.", error.message)
        }
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
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake))))
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

        fake.focused = "a"
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(FocusAction(.left))), id: "focus")
            check("S-068 no window that way says so", false, "no failure")
        } catch {
            check("S-068 no window that way says so", error.message == "No window to the left." && fake.focused == "a", error.message)
        }
    }

    /// S-070: the window types in the Type picker, and each form's value
    /// saved as the spec writes it, then undone.
    static func windowEditingChecks(_ model: AppModel) async {
        let names = Config.Action.types(allowsContextAware: true).map { Config.Action.empty(of: $0).displayName }
        let window = ["Focus Window", "Maximize", "Minimize", "Move Window", "Place Window", "Resize Window"]
        check("S-070 the Type picker lists the window actions with the others, alphabetically",
              Set(window).isSubset(of: names) && names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(names)")

        let editor = model.editor
        editor.reloadFromStore()
        let undo = UndoManager()
        undo.groupsByEvent = false
        func file() -> String { (try? String(contentsOf: model.store.url, encoding: .utf8)) ?? "" }
        let before = file()
        let cases: [(Config.Action, String)] = [
            (.family(AnyActionValue(FocusAction(.previous))), #"{ "type": "window.focus", "direction": "previous" }"#),
            (.family(AnyActionValue(MaximizeAction(toggle: false))), #"{ "type": "window.maximize", "toggle": false }"#),
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
        while undo.canUndo { undo.undo() }
        check("S-070 Undo restores the file", file() == before)
    }
}
