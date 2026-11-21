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
}
