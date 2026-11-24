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
        await swapChecks()
        await seenChecks()
        await recentChecks()
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

    /// S-070: the window types in the Type picker, and each form's value
    /// saved as the spec writes it, then undone.
    static func windowEditingChecks(_ model: AppModel) async {
        let names = Config.Action.types(allowsContextAware: true).map { Config.Action.empty(of: $0).displayName }
        let window = ["Arrange Windows", "Fill", "Focus Window", "Minimize", "Move Window", "Place Window", "Resize Window", "Swap Window", "Switch Space"]
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
            (.family(AnyActionValue(FocusAction(.previous))), #"{ "type": "window.focus", "target": "previous" }"#),
            (.family(AnyActionValue(FocusAction(.number(3)))), #"{ "type": "window.focus", "target": 3 }"#),
            (.family(AnyActionValue(FocusAction(.next, scope: .display))), #"{ "type": "window.focus", "target": "next", "scope": "display" }"#),
            (.family(AnyActionValue(SwapAction(.number(2), scope: .display))), #"{ "type": "window.swap", "target": 2, "scope": "display" }"#),
            (.family(AnyActionValue(SwapAction(.window(.left)))), #"{ "type": "window.swap", "target": "left" }"#),
            (.family(AnyActionValue(SpaceSwitchAction(.left))), #"{ "type": "space.switch", "target": "left" }"#),
            (.family(AnyActionValue(SpaceSendAction(.number(2), follow: true))), #"{ "type": "space.follow", "target": 2 }"#),
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
        undo.beginUndoGrouping()
        editor.edit("Change Smallest Visible Part", undo: undo) { $0.config.windows.minVisible = 40 }
        undo.endUndoGrouping()
        check("S-082 Smallest Visible Part is saved in the file's windows settings, and undoes",
              file().contains(#""minVisible": 40"#) && { undo.undo(); return !file().contains("minVisible") }())
        undo.beginUndoGrouping()
        editor.edit("Change App Rules", undo: undo) { $0.config.windows.apps = ["com.apple.calculator": .init(arrange: false)] }
        undo.endUndoGrouping()
        check("S-084 an app's rules are saved in the file's windows settings, all four, and undo",
              file().contains(#""apps": { "com.apple.calculator": { "focus": true, "swap": true, "arrange": false, "quit": true } }"#)
                  && { undo.undo(); return !file().contains("com.apple.calculator") }())
        undo.beginUndoGrouping()
        editor.edit("Change Quit on Close", undo: undo) { $0.config.windows.quitOnClose = true }
        editor.edit("Change Wait After Closing", undo: undo) { $0.config.windows.quitOnCloseDelayMs = 1200 }
        editor.edit("Change App Rules", undo: undo) { $0.config.windows.apps = ["com.apple.Preview": .init(quit: false)] }
        undo.endUndoGrouping()
        check("S-086 Quit on Close, its wait and an app's Quit rule are saved in the file's windows settings, and undo",
              file().contains(#""quitOnClose": true"#) && file().contains(#""quitOnCloseDelayMs": 1200"#)
                  && file().contains(#""com.apple.Preview": { "focus": true, "swap": true, "arrange": true, "quit": false }"#)
                  && model.store.loaded?.config.windows.quitOnClose == true
                  && { undo.undo(); return !file().contains("quitOnClose") && !file().contains("com.apple.Preview") }())

        // S-080: choosing a built-in action saves only its name; an override in use can be deleted.
        let builtIn = "window-place-right-half"
        if let path = editor.draft.config.entries.first(where: { $0.action != nil }).flatMap({ KeySequence(parsing: $0.keys) }) {
            undo.beginUndoGrouping()
            editor.setAction(path, builtIn, undo: undo)
            undo.endUndoGrouping()
            let saved = model.store.loaded?.config
            check("S-080 choosing a built-in action saves its name and nothing in actions",
                  file().contains(#""action": "\#(builtIn)""#) && saved?.actions[builtIn] == nil
                      && saved?.action(named: builtIn) == .family(AnyActionValue(PlaceAction.preset(.rightHalf))))
            undo.beginUndoGrouping()
            editor.edit("Change Action", undo: undo) { $0.setAction(id: builtIn, .family(AnyActionValue(PlaceAction.preset(.leftHalf)))) }
            undo.endUndoGrouping()
            let overridden = model.store.loaded?.config.action(named: builtIn)
            var refused = false
            undo.beginUndoGrouping()
            editor.edit("Delete Action", undo: undo) { document in
                do throws(ConfigDocument.EditError) { try document.removeAction(builtIn) } catch { refused = true }
            }
            undo.endUndoGrouping()
            check("S-080 an override runs instead, and deleting it while in use gives the built-in one back",
                  overridden == .family(AnyActionValue(PlaceAction.preset(.leftHalf))) && !refused
                      && model.store.loaded?.config.action(named: builtIn) == .family(AnyActionValue(PlaceAction.preset(.rightHalf))))
        } else {
            check("S-080 the self-test config has a binding", false)
        }
        while undo.canUndo { undo.undo() }
        check("S-070 Undo restores the file", file() == before)
    }
}
