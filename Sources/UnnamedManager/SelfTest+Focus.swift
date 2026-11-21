import Foundation
import UnnamedManagerKit

extension SelfTest {
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
}
