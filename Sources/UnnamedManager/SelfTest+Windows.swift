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
        check("S-076 All gives the focused window the whole column it's in and stacks the two others in the other one",
              frame("browser") == right && frame("editor") == CGRect(x: 8, y: 467, width: 708, height: 425)
                  && frame("notes") == CGRect(x: 8, y: 33, width: 708, height: 426) && frame("away") == away,
              "\(String(describing: frame("browser"))), \(String(describing: frame("editor"))), \(String(describing: frame("notes")))")

        // A window in the left column gets focus: it fills that column, and the two others stack on the right.
        fake.focused = "notes"
        fake.stacking = ["notes", "browser", "editor", "away"]
        _ = await run(ArrangeAction(count: .all))
        check("S-076 run again from a window on the left, that one fills the left column where it is",
              frame("notes") == left && frame("browser") == CGRect(x: 724, y: 33, width: 708, height: 426)
                  && frame("editor") == CGRect(x: 724, y: 467, width: 708, height: 425),
              "\(String(describing: frame("notes"))), \(String(describing: frame("browser"))), \(String(describing: frame("editor")))")

        settings.maxColumns = 3
        _ = await run(ArrangeAction(count: .all))
        check("S-076 with Maximum Columns at 3, the three are columns, 8 points apart",
              frame("editor") == CGRect(x: 964, y: 33, width: 468, height: 859) && frame("browser") == CGRect(x: 484, y: 33, width: 472, height: 859)
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
        check("S-073 First and Last go to the first and last window in the order, with or without a focused one",
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

    /// S-077 and S-078: Swap Window, and both actions on one display, with
    /// two halves of the left display and a window on the right one.
    static func swapChecks() async {
        let fake = FakeWindowSystem()
        fake.displays = [
            .init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), usable: CGRect(x: 0, y: 25, width: 1440, height: 875)),
            .init(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), usable: CGRect(x: 1440, y: 25, width: 1920, height: 1055)),
        ]
        let a = CGRect(x: 0, y: 25, width: 720, height: 875)
        let b = CGRect(x: 720, y: 25, width: 720, height: 875)
        let c = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        func reset() {
            fake.windows = ["a": .init(frame: a), "b": .init(frame: b), "c": .init(frame: c)]
            fake.focused = "b"
        }
        func frames() -> [CGRect?] { ["a", "b", "c"].map { fake.windows[$0]?.frame } }
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { Config.Windows(gap: 0) }))))
        /// Runs an action and returns its failure, if any.
        func run(_ action: some ActionValue) async -> PlanError? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "swap")
                return nil
            } catch {
                return error
            }
        }

        reset()
        _ = await run(SwapAction(.window(.left)))
        check("S-077 Swap left trades frames with the window on the left, and focus stays",
              frames() == [b, a, c] && fake.focused == "b", "\(frames()), \(String(describing: fake.focused))")
        _ = await run(SwapAction(.window(.right)))
        check("S-077 and Swap right puts them back", frames() == [a, b, c], "\(frames())")

        reset()
        _ = await run(SwapAction(.number(3)))
        check("S-077 a number swaps across displays", frames() == [a, c, b] && fake.focused == "b", "\(frames())")

        reset()
        _ = await run(SwapAction(.window(.next), scope: .display))
        let here = frames()
        reset()
        _ = await run(SwapAction(.window(.next)))
        check("S-078 Next on the same display wraps there, and on every display goes on to the next",
              here == [b, a, c] && frames() == [a, c, b], "\(here), \(frames())")

        reset()
        fake.focused = "a"
        let left = await run(SwapAction(.window(.left)))
        let past = await run(SwapAction(.number(4)))
        check("S-077 no window there: nothing moves, it says so, and it plays the alert sound",
              frames() == [a, b, c] && left == PlanError("No window to the left.", alerts: true)
                && past == PlanError("No window 4. There are 3.", alerts: true),
              "\(String(describing: left)), \(String(describing: past))")
        let first = await run(SwapAction(.window(.first)))
        check("S-077 First on the first window does nothing, and isn't a failure", first == nil && frames() == [a, b, c])
        fake.focused = nil
        let unfocused = await run(SwapAction(.window(.right)))
        check("S-077 no focused window says so, with no alert sound",
              unfocused == PlanError("TextEdit has no window to swap."), "\(String(describing: unfocused))")

        reset()
        fake.windows["b"]?.minSize = CGSize(width: 900, height: 300)
        _ = await run(SwapAction(.window(.left)))
        check("S-077 a window that won't take the size keeps the edge on the screen's edge",
              fake.windows["b"]?.frame == CGRect(x: 0, y: 25, width: 900, height: 875) && fake.windows["a"]?.frame == b,
              "\(frames())")

        reset()
        let blocked = await run(FocusAction(.right, scope: .display))
        let stayed = fake.focused
        _ = await run(FocusAction(.right))
        check("S-078 Focus Window on the same display stays there, and on every display crosses over",
              blocked == PlanError("No window to the right.", alerts: true) && stayed == "b" && fake.focused == "c",
              "\(String(describing: blocked)), \(String(describing: stayed)), \(String(describing: fake.focused))")
        fake.focused = "a"
        _ = await run(FocusAction(.last, scope: .display))
        check("S-078 Last on the same display is the rightmost window there", fake.focused == "b", "\(String(describing: fake.focused))")

        // S-079: Focus Window by number, and built-in names run as a binding runs them.
        fake.focused = "a"
        _ = await run(FocusAction(.number(3)))
        let third = fake.focused
        let beyond = await run(FocusAction(.number(4)))
        check("S-079 Focus Window 3 goes to the third window, and 4 says there are 3, with the alert sound",
              third == "c" && fake.focused == "c" && beyond == PlanError("No window 4. There are 3.", alerts: true),
              "\(String(describing: third)), \(String(describing: beyond))")
        fake.focused = nil
        _ = await run(FocusAction(.number(2)))
        check("S-079 a number needs no focused window", fake.focused == "b", "\(String(describing: fake.focused))")

        reset()
        let config = Config(entries: [], actions: ["window-focus-left": .family(AnyActionValue(BasicAction.noop))])
        if let swap = config.action(named: "window-swap-left"), let focus = config.action(named: "window-focus-left") {
            try? await runner.run(swap, id: "window-swap-left")
            try? await runner.run(focus, id: "window-focus-left")
        }
        check("S-079 a built-in name runs its action, and an action with that name overrides it",
              frames() == [b, a, c] && fake.focused == "b", "\(frames()), \(String(describing: fake.focused))")
    }

    /// S-082: two windows stacked on the left half with one on the right,
    /// then a small window inside a large one. Focusing raises a window.
    static func seenChecks() async {
        let fake = FakeWindowSystem()
        fake.displays = [.init(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), usable: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        let half = CGRect(x: 0, y: 0, width: 960, height: 1080), right = CGRect(x: 960, y: 0, width: 960, height: 1080)
        func reset() {
            fake.windows = ["front": .init(frame: half), "hidden": .init(frame: half), "right": .init(frame: right)]
            fake.stacking = ["front", "hidden", "right"]
            fake.focused = "front"
        }
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { Config.Windows(gap: 0) }))))
        func run(_ action: some ActionValue) async -> PlanError? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "seen")
                return nil
            } catch {
                return error
            }
        }

        reset()
        var visits: [String] = []
        for action in [FocusAction(.right), FocusAction(.left), FocusAction(.next), FocusAction(.next)] {
            _ = await run(action)
            visits.append(fake.focused ?? "none")
        }
        let third = await run(FocusAction(.number(3)))
        check("S-082 Focus Window skips a window hidden behind another, by direction, Next and number",
              visits == ["right", "front", "right", "front"] && third == PlanError("No window 3. There are 2.", alerts: true),
              "\(visits), \(String(describing: third))")

        reset()
        _ = await run(SwapAction(.window(.next)))
        check("S-082 Swap Window skips a hidden window too",
              fake.windows["front"]?.frame == right && fake.windows["right"]?.frame == half && fake.windows["hidden"]?.frame == half)

        let small = CGRect(x: 500, y: 300, width: 400, height: 300)
        fake.windows = ["small": .init(frame: small), "large": .init(frame: fake.displays[0].frame)]
        fake.stacking = ["small", "large"]
        fake.focused = "small"
        _ = await run(FocusAction(.left))
        let left = fake.focused
        let back = await run(FocusAction(.right))
        check("S-082 from a window inside a larger one, a direction goes to the larger one, which then hides it",
              left == "large" && fake.focused == "large" && back == PlanError("No window to the right.", alerts: true),
              "\(String(describing: left)), \(String(describing: back))")
    }

    /// S-083: the window used before, from the focus history, across
    /// displays, Spaces and windows on top; and apps left out.
    static func recentChecks() async {
        let fake = FakeWindowSystem()
        let left = CGRect(x: 0, y: 0, width: 960, height: 1080), whole = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let other = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        fake.displays = [.init(frame: whole, usable: whole), .init(frame: other, usable: other)]
        var settings = Config.Windows(gap: 0)
        var runner = ActionRunner()
        /// New windows, and a new history.
        func start(_ windows: [String: FakeWindowSystem.Window], clicks: [String]) {
            fake.windows = windows
            fake.stacking = []
            fake.currentSpace = 1
            runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { settings }))))
            clicks.forEach(fake.click)
        }
        func run(_ action: some ActionValue) async -> PlanError? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "recent")
                return nil
            } catch {
                return error
            }
        }
        let recent = FocusAction(.recent), swap = SwapAction(.window(.recent))

        start(["a": .init(frame: left), "b": .init(frame: other)], clicks: ["a", "b"])
        var visits: [String] = []
        for _ in 0..<3 {
            _ = await run(recent)
            visits.append(fake.focused ?? "none")
        }
        check("S-083 Focus Window's recent goes back and forth between two windows, across displays",
              visits == ["a", "b", "a"], "\(visits)")

        start(["under": .init(frame: whole), "top": .init(frame: whole)], clicks: ["under", "top"])
        _ = await run(recent)
        check("S-083 the window used before counts when it's fully covered", fake.focused == "under")

        start(["a": .init(frame: left), "c": .init(frame: left, space: 2)], clicks: ["a", "c"])
        let away = fake.currentSpace
        _ = await run(recent)
        check("S-083 the window used before can be on another Space, and focusing it moves there",
              away == 2 && fake.focused == "a" && fake.currentSpace == 1, "Space \(away), then \(fake.currentSpace)")

        start(["a": .init(frame: left), "b": .init(frame: left), "c": .init(frame: left)], clicks: ["a", "b", "c"])
        fake.windows["b"] = nil
        _ = await run(recent)
        let closed = fake.focused
        start(["a": .init(frame: left)], clicks: ["a"])
        let alone = await run(recent)
        check("S-083 with the window used before closed, it's the one before that; with no other window, it fails with the sound",
              closed == "a" && alone == PlanError("No window used before.", alerts: true), "\(String(describing: closed)), \(String(describing: alone))")

        start(["a": .init(frame: left), "b": .init(frame: other)], clicks: ["a", "b"])
        _ = await run(swap)
        let swapped = (fake.windows["a"]?.frame, fake.windows["b"]?.frame, fake.focused)
        _ = await run(swap)
        check("S-083 Swap Window's recent trades frames with the window used before, keeps focus, and swaps back",
              swapped == (other, left, "b") && fake.windows["a"]?.frame == left && fake.windows["b"]?.frame == other && fake.focused == "b")

        start(["d": .init(frame: left), "a": .init(frame: left, space: 2), "b": .init(frame: other)], clicks: ["d", "a", "b"])
        _ = await run(swap)
        check("S-083 Swap Window's recent skips a window on another Space",
              fake.windows["d"]?.frame == other && fake.windows["b"]?.frame == left && fake.windows["a"]?.frame == left)

        settings.apps = ["com.example.skip": .init(focus: false)]
        start(["a": .init(frame: left), "x": .init(frame: CGRect(x: 960, y: 0, width: 960, height: 1080), app: "com.example.skip"),
               "b": .init(frame: other)], clicks: ["a", "x", "b"])
        _ = await run(recent)
        let skipped = fake.focused
        _ = await run(FocusAction(.right))
        check("S-083 an app with focus false is never picked by Focus Window, by recent or a direction",
              skipped == "a" && fake.focused == "b", "\(String(describing: skipped)), \(String(describing: fake.focused))")

        // S-084: each app's rules, apart from each other.
        let calc = "com.example.calc", small = CGRect(x: 100, y: 100, width: 300, height: 300)
        let leftHalf = CGRect(x: 0, y: 0, width: 960, height: 1080), rightHalf = CGRect(x: 960, y: 0, width: 960, height: 1080)
        settings.apps = [calc: .init(arrange: false)]
        start(["a": .init(frame: CGRect(x: 0, y: 0, width: 800, height: 600)), "b": .init(frame: CGRect(x: 1000, y: 0, width: 800, height: 600)),
               "c": .init(frame: small, app: calc)], clicks: ["b", "c", "a"])
        _ = await run(ArrangeAction())
        check("S-084 Arrange Windows never counts or moves a window of an app with arrange false",
              fake.windows["a"]?.frame == leftHalf && fake.windows["b"]?.frame == rightHalf && fake.windows["c"]?.frame == small,
              "\(fake.windows.mapValues(\.frame))")
        _ = await run(recent)
        check("S-084 Focus Window still picks a window of an app with arrange false", fake.focused == "c", "\(String(describing: fake.focused))")

        // A dialog, as many Settings windows are: Focus Window picks it, Swap Window and Arrange Windows never move it.
        settings.apps = [:]
        start(["a": .init(frame: CGRect(x: 0, y: 0, width: 800, height: 600)), "b": .init(frame: CGRect(x: 1000, y: 0, width: 800, height: 600)),
               "s": .init(frame: small, isDialog: true)], clicks: ["b", "s", "a"])
        _ = await run(ArrangeAction())
        check("Arrange Windows never counts or moves a dialog",
              fake.windows["a"]?.frame == leftHalf && fake.windows["b"]?.frame == rightHalf && fake.windows["s"]?.frame == small,
              "\(fake.windows.mapValues(\.frame))")
        _ = await run(recent)
        check("Focus Window picks a dialog", fake.focused == "s", "\(String(describing: fake.focused))")
        let refused = await run(swap)
        check("Swap Window never moves a focused dialog", refused?.message == "A dialog is left out of Swap Window."
              && fake.windows["s"]?.frame == small && fake.windows["a"]?.frame == leftHalf, refused?.message ?? "no failure")
        fake.click("a")
        _ = await run(swap)
        check("Swap Window's recent skips a dialog for the window before it",
              fake.windows["s"]?.frame == small && fake.windows["a"]?.frame == rightHalf && fake.windows["b"]?.frame == leftHalf,
              "\(fake.windows.mapValues(\.frame))")
        settings.apps = [calc: .init(arrange: false)]

        let d = CGRect(x: 1920, y: 0, width: 800, height: 600), e = CGRect(x: 2920, y: 0, width: 800, height: 600)
        start(["a": .init(frame: CGRect(x: 0, y: 0, width: 800, height: 600)), "d": .init(frame: d), "e": .init(frame: e),
               "c": .init(frame: other.insetBy(dx: 400, dy: 300), app: calc)], clicks: ["a", "e", "d", "c"])
        _ = await run(ArrangeAction())
        check("S-084 with the focused window left out, its display is arranged, the window in front there first",
              fake.windows["d"]?.frame == CGRect(x: 1920, y: 0, width: 960, height: 1080)
                  && fake.windows["e"]?.frame == CGRect(x: 2880, y: 0, width: 960, height: 1080)
                  && fake.windows["a"]?.frame == CGRect(x: 0, y: 0, width: 800, height: 600)
                  && fake.windows["c"]?.frame == other.insetBy(dx: 400, dy: 300),
              "\(fake.windows.mapValues(\.frame))")

        settings.apps = [calc: .init(focus: false, swap: false)]
        start(["a": .init(frame: CGRect(x: 0, y: 0, width: 800, height: 600)), "c": .init(frame: CGRect(x: 1000, y: 0, width: 800, height: 600), app: calc)],
              clicks: ["c", "a"])
        _ = await run(ArrangeAction())
        check("S-084 Arrange Windows still arranges an app with focus and swap false",
              fake.windows["a"]?.frame == leftHalf && fake.windows["c"]?.frame == rightHalf, "\(fake.windows.mapValues(\.frame))")

        _ = await run(SwapAction(.window(.right)))
        let kept = fake.windows["a"]?.frame == leftHalf && fake.windows["c"]?.frame == rightHalf
        fake.click("c")
        let fromLeftOut = await run(SwapAction(.window(.left)))
        check("S-084 Swap Window never moves a window of an app with swap false, as the one swapped with or the focused one",
              kept && fake.windows["a"]?.frame == leftHalf && fromLeftOut?.message.hasSuffix("is left out of Swap Window.") == true,
              "\(String(describing: fromLeftOut?.message))")

        settings.apps = [calc: .init(focus: false)]
        start(["a": .init(frame: leftHalf), "c": .init(frame: rightHalf, app: calc)], clicks: ["c", "a"])
        _ = await run(SwapAction(.window(.right)))
        check("S-084 Swap Window still swaps with an app with only focus false",
              fake.windows["a"]?.frame == rightHalf && fake.windows["c"]?.frame == leftHalf, "\(fake.windows.mapValues(\.frame))")
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
            (.family(AnyActionValue(SpaceSendAction(.number(2), follow: true))), #"{ "type": "space.send", "target": 2, "follow": true }"#),
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

    /// S-087, against test domains: the real Dock and Spaces settings never change.
    static func spacesChecks(_ model: AppModel) {
        let spaces = model.spaces
        let prefs = spaces.preferences
        check("S-087 the self-test reads and writes test domains, not com.apple.dock",
              prefs.domain(.rearrangeByRecentUse) != "com.apple.dock" && prefs.domain(.separateSpaces) != "com.apple.spaces")
        check("S-087 unset, Rearrange is on and suggested off, Separate Spaces on as suggested",
              spaces.unsuggested == [.rearrangeByRecentUse], "\(spaces.unsuggested)")
        let restarts = spaces.dockRestarts
        spaces.set(.rearrangeByRecentUse, isOn: false)
        check("S-087 turning Rearrange off writes mru-spaces false and restarts the Dock once",
              prefs.stored(.rearrangeByRecentUse) == false && spaces.dockRestarts == restarts + 1 && spaces.unsuggested.isEmpty)
        spaces.set(.separateSpaces, isOn: false)
        check("S-087 turning Separate Spaces off writes spans-displays true, restarts nothing, and waits for log out",
              prefs.stored(.separateSpaces) == true && spaces.dockRestarts == restarts + 1 && spaces.waitsForLogOut
                  && spaces.unsuggested == [.separateSpaces])
        spaces.set(.separateSpaces, isOn: true)
        check("S-087 turning it back on writes spans-displays false and no longer waits",
              prefs.stored(.separateSpaces) == false && !spaces.waitsForLogOut)
        SpacesSetting.allCases.forEach(prefs.remove)
        spaces.refresh()
    }

    /// S-088, against FakeWindowSystem: nothing reaches the real Dock.
    static func spaceSwitchChecks() async {
        let fake = FakeWindowSystem()
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900), other = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        fake.displays = [.init(frame: main, usable: main), .init(frame: other, usable: other)]
        fake.windows = ["a": .init(frame: CGRect(x: 1500, y: 100, width: 800, height: 600))]
        fake.focused = "a"
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake))))
        func run(_ name: String) async -> PlanError? {
            guard let action = BuiltInAction.action(named: name) else { return PlanError("No \(name)") }
            do throws(PlanError) {
                try await runner.run(action, id: name)
                return nil
            } catch {
                return error
            }
        }
        let right = await run("space-switch-right")
        check("S-088 space-switch-right switches once, to the right, on the focused window's display",
              right == nil && fake.spaceSwitches.count == 1 && fake.spaceSwitches.first?.direction == .right
                  && fake.spaceSwitches.first?.screen == other && fake.currentSpace == 2,
              "\(String(describing: right)) \(fake.spaceSwitches)")
        _ = await run("space-switch-right")
        let pastTheEnd = await run("space-switch-right")
        check("S-088 at the last Space it isn't a failure", pastTheEnd == nil && fake.currentSpace == 3)
        _ = await run("space-switch-left")
        check("S-088 space-switch-left goes back one Space", fake.spaceSwitches.last?.direction == .left && fake.currentSpace == 2)
        fake.focused = nil
        let count = fake.spaceSwitches.count
        let none = await run("space-switch-left")
        check("S-088 with no focused window, nothing is posted and it isn't a failure",
              none == nil && fake.spaceSwitches.count == count)
        fake.focused = "a"
        fake.canControlWindows = false
        let denied = await run("space-switch-left")
        check("S-088 without Accessibility it fails and says so", denied?.message.contains("Accessibility") == true && fake.spaceSwitches.count == count)
    }

    /// S-096, against FakeWindowSystem: no real window leaves its Space.
    static func spaceSendChecks() async {
        let fake = FakeWindowSystem()
        let left = CGRect(x: 24, y: 48, width: 680, height: 828), right = CGRect(x: 736, y: 48, width: 680, height: 828)
        fake.windows = ["a": .init(frame: left, pid: 1, app: "com.apple.TextEdit"),
                        "b": .init(frame: right, pid: 2, app: "com.apple.Safari"),
                        "c": .init(frame: right, pid: 3, app: "com.apple.Notes", space: 2)]
        fake.lastSpace = 4
        let control = WindowControl(system: fake)
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: control)))
        func run(_ action: SpaceSendAction) async -> PlanError? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "send")
                return nil
            } catch {
                return error
            }
        }
        fake.click("b")
        fake.click("a")
        let sent = await run(SpaceSendAction(.number(3)))
        check("S-096 space.send 3 puts the window on Space 3, and you stay",
              sent == nil && fake.windows["a"]?.space == 3 && fake.currentSpace == 1 && fake.sends.map(\.desktop) == [3],
              "\(String(describing: sent)) \(fake.sends)")
        check("S-096 without follow, the window used before on this Space takes focus", fake.focused == "b", "\(String(describing: fake.focused))")
        let back = await run(SpaceSendAction(.side(.left)))
        check("S-096 left from Space 1 does nothing, with no sound",
              back == nil && fake.sends.count == 1 && fake.windows["b"]?.space == 1)
        let followed = await run(SpaceSendAction(.side(.right), follow: true))
        check("S-096 right with follow takes the window and you to Space 2, and it keeps focus",
              followed == nil && fake.windows["b"]?.space == 2 && fake.currentSpace == 2 && fake.focused == "b",
              "\(String(describing: followed)) space \(fake.currentSpace) focused \(String(describing: fake.focused))")
        let same = await run(SpaceSendAction(.number(2)))
        check("S-096 a number for the window's own Space does nothing", same == nil && fake.sends.count == 2)
        let past = await run(SpaceSendAction(.number(5)))
        check("S-096 a number past the last Space fails with the sound",
              past == PlanError("No Space 5. There are 4.", alerts: true) && fake.sends.count == 2, "\(String(describing: past))")
        let builtIn = BuiltInAction.action(named: "space-send-4")
        check("S-096 space-send-4 is a built-in action with follow off",
              builtIn == .family(AnyActionValue(SpaceSendAction(.number(4)))))
        fake.windows["b"]?.place = .fullScreen
        let full = await run(SpaceSendAction(.number(1)))
        check("S-096 a full-screen window can't be sent, with the sound", full?.alerts == true && full?.message.contains("full screen") == true)
        fake.windows["b"]?.place = .everySpace
        let every = await run(SpaceSendAction(.number(1)))
        check("S-096 a window on every Space can't be sent, with the sound", every?.alerts == true && every?.message.contains("every Space") == true)
        fake.windows["b"]?.place = .desktop
        fake.refusesSend = true
        let refused = await run(SpaceSendAction(.number(1)))
        check("S-096 when macOS refuses, it fails with the sound", refused?.alerts == true && fake.windows["b"]?.space == 2)
        fake.refusesSend = false
        fake.focused = nil
        let none = await run(SpaceSendAction(.number(1)))
        check("S-096 with no focused window it fails with the sound", none == PlanError("No window to send.", alerts: true))
        fake.focused = "b"
        fake.canControlWindows = false
        let denied = await run(SpaceSendAction(.number(1)))
        check("S-096 without Accessibility it fails and says so", denied?.message.contains("Accessibility") == true)
    }
}
