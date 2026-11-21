import Foundation
import UnnamedManagerKit

extension SelfTest {
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
        check("S-087 Reduce Motion off is a tip, never a suggestion in the menu bar menu",
              !spaces.reducesMotion && spaces.unsuggested.isEmpty && spaces.reduceMotionNote.contains("Accessibility › Motion"),
              spaces.reduceMotionNote)
        spaces.testReducesMotion = true
        spaces.refresh()
        check("S-087 with Reduce Motion on, the Windows tab says Spaces fade",
              spaces.reducesMotion && spaces.reduceMotionNote.contains("fade") && spaces.unsuggested.isEmpty)
        spaces.testReducesMotion = false
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
        let swipes = fake.spaceSwitches.count
        let followed = await run(SpaceSendAction(.side(.right), follow: true))
        check("S-096 right with follow takes the window and you to Space 2, and it keeps focus",
              followed == nil && fake.windows["b"]?.space == 2 && fake.currentSpace == 2 && fake.focused == "b",
              "\(String(describing: followed)) space \(fake.currentSpace) focused \(String(describing: fake.focused))")
        check("S-096 follow goes with one swipe to the right, on the window's display, with no slide",
              fake.spaceSwitches.dropFirst(swipes).map(\.direction) == [.right]
                  && fake.spaceSwitches.last?.screen == fake.screens().first(where: { $0.frame.contains(right) })?.frame,
              "\(fake.spaceSwitches.dropFirst(swipes))")
        let same = await run(SpaceSendAction(.number(2)))
        check("S-096 a number for the window's own Space does nothing", same == nil && fake.sends.count == 2)
        let past = await run(SpaceSendAction(.number(5)))
        check("S-096 a number past the last Space fails with the sound",
              past == PlanError("No Space 5. There are 4.", alerts: true) && fake.sends.count == 2, "\(String(describing: past))")
        let far = fake.spaceSwitches.count
        let jumped = await run(SpaceSendAction(.number(4), follow: true))
        check("S-096 follow to Space 4 from Space 2 swipes right twice, and you arrive with the window",
              jumped == nil && fake.spaceSwitches.dropFirst(far).map(\.direction) == [.right, .right]
                  && fake.windows["b"]?.space == 4 && fake.currentSpace == 4 && fake.focused == "b",
              "\(String(describing: jumped)) \(fake.spaceSwitches.dropFirst(far)) space \(fake.currentSpace)")
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
        check("S-096 when macOS refuses, it fails with the sound", refused?.alerts == true && fake.windows["b"]?.space == 4)
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
