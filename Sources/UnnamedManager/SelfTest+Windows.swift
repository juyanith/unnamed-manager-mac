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

        fake.canControlWindows = false
        do throws(PlanError) {
            try await runner.run(maximize, id: "maximize")
            check("S-062 without Accessibility, window actions say what to allow", false, "no failure")
        } catch {
            check("S-062 without Accessibility, window actions say what to allow",
                  error.message == "Unnamed Manager needs Accessibility access to move windows.", error.message)
        }
    }
}
