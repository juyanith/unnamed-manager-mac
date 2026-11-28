import Foundation
import UnnamedManagerKit

extension SelfTest {
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

        settings.minCell = WindowSteps(across: 4, down: 6)
        _ = await run(ArrangeAction(count: .all))
        check("S-076 with the smallest cell 4 steps across, of 12, the three are columns, 8 points apart",
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
}

extension SelfTest {
    /// Tidy Windows and Undo Layout (S-099, S-100, spec v24) on a 1440 by
    /// 900 display, 12 by 12 steps of 120 points across, with a gap of 8.
    static func tidyChecks() async {
        let fake = FakeWindowSystem()
        let roughLeft = CGRect(x: 10, y: 40, width: 700, height: 840), roughRight = CGRect(x: 730, y: 30, width: 700, height: 850)
        let calculator = CGRect(x: 600, y: 400, width: 230, height: 300)
        fake.windows = ["left": .init(frame: roughLeft), "right": .init(frame: roughRight),
                        "calc": .init(frame: calculator, app: "com.apple.calculator")]
        fake.stacking = ["calc", "right", "left"]
        fake.focused = "left"
        let settings = Config.Windows(gap: 8, apps: ["com.apple.calculator": .init(arrange: false)])
        let runner = ActionRunner(performer: SystemPerformer(context: StepContext(windows: WindowControl(system: fake, settings: { settings }))))
        func frame(_ id: String) -> CGRect? { fake.windows[id]?.frame }
        func run(_ action: some ActionValue) async -> PlanError? {
            do throws(PlanError) {
                try await runner.run(.family(AnyActionValue(action)), id: "layout")
                return nil
            } catch {
                return error
            }
        }
        let left = CGRect(x: 8, y: 33, width: 708, height: 859), right = CGRect(x: 724, y: 33, width: 708, height: 859)

        _ = await run(TidyAction())
        check("S-099 two rough halves meet at the step nearest the middle and fill the display, 8 points apart",
              frame("left") == left && frame("right") == right, "\(String(describing: frame("left"))), \(String(describing: frame("right")))")
        check("S-099 an app left out of Arrange Windows isn't moved, and the focus stays", frame("calc") == calculator && fake.focused == "left")
        _ = await run(TidyAction())
        check("S-099 a tidy layout doesn't move when tidied again", frame("left") == left && frame("right") == right)

        _ = await run(UndoLayoutAction())
        check("S-100 Undo Layout puts the windows back where they were, even after a tidy that moved nothing",
              frame("left") == roughLeft && frame("right") == roughRight)
        _ = await run(UndoLayoutAction())
        check("S-100 pressed again, it puts the layout back", frame("left") == left && frame("right") == right)

        let moved = CGRect(x: 100, y: 100, width: 500, height: 500)
        fake.windows["left"]?.frame = moved
        _ = await run(UndoLayoutAction())
        check("S-100 a window moved since stays where it is; the others go back", frame("left") == moved && frame("right") == roughRight)
        fake.windows["right"]?.frame = moved
        let failure = await run(UndoLayoutAction())
        check("S-100 with every window moved since, there's nothing to undo, with the alert sound",
              failure?.message == "Nothing to undo." && failure?.alerts == true, failure?.message ?? "no failure")

        fake.windows["left"]?.frame = roughLeft
        fake.windows["right"]?.frame = roughRight
        _ = await run(ArrangeAction())
        _ = await run(UndoLayoutAction())
        check("S-100 Undo Layout also puts back what Arrange Windows moved", frame("left") == roughLeft && frame("right") == roughRight)

        fake.windows = ["calc": .init(frame: calculator, app: "com.apple.calculator")]
        let none = await run(TidyAction())
        check("S-099 with only a left-out app's window, there's no window to tidy", none?.message == "No window to tidy.", none?.message ?? "no failure")
    }
}
