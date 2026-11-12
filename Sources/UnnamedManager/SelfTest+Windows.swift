import CoreGraphics
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
        fake.focused = "a"
        do throws(PlanError) {
            try await runner.run(.family(AnyActionValue(FocusAction(.left))), id: "focus")
            check("S-068 no window that way says so", false, "no failure")
        } catch {
            check("S-068 no window that way says so", error.message == "No window to the left." && fake.focused == "a", error.message)
        }
    }
}
