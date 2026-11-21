import Foundation
import UnnamedManagerKit

extension SelfTest {
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
}
