import Foundation
import Testing
@testable import UnnamedManagerKit

private let leader = BindingNode(path: KeySequence(parsing: "Hyper+Space")!, title: "Commands", action: nil, children: [])
private let apps = BindingNode(path: KeySequence(parsing: "Hyper+Space A")!, title: "Applications", action: nil, children: [])
private let binding = BindingNode(path: KeySequence(parsing: "Hyper+Space E")!, title: "Editor", action: "edit", children: [])

private func schedule(delay: Int = 0, timeout: Int = 0, showHud: Bool = true, flash: Bool = true, bell: Bool = true) -> GuideSchedule {
    var runtime = Config.Runtime()
    runtime.hudDelayMs = delay
    runtime.timeoutMs = timeout
    runtime.showHud = showHud
    var ui = Config.UI()
    ui.errorFlash = flash
    ui.errorBell = bell
    return GuideSchedule(runtime: runtime, ui: ui)
}

private func open(_ menu: BindingNode, _ path: [String] = ["Commands"]) -> SequenceEffect {
    .showMenu(menu, path: path, frontApp: nil)
}
private func shown(_ menu: BindingNode, _ path: [String] = ["Commands"]) -> GuideCommand {
    .show(menu, path: path, frontApp: nil)
}

@Suite("Guide delay (S-016)")
struct GuideDelayTests {
    @Test("With no delay the Guide shows with the leader")
    func noDelay() {
        var s = schedule()
        #expect(s.handle(open(leader), at: 0) == [shown(leader)])
        #expect(s.isVisible)
    }

    @Test("The Guide shows only after the delay passes with no key press")
    func delay() {
        var s = schedule(delay: 500)
        #expect(s.handle(open(leader), at: 0) == [])
        #expect(s.nextDeadline == 500)
        #expect(s.tick(at: 499) == [])
        #expect(s.tick(at: 500) == [shown(leader)])
        #expect(s.isVisible)
    }

    @Test("A known sequence finished inside the delay shows nothing")
    func fast() {
        var s = schedule(delay: 500)
        _ = s.handle(open(leader), at: 0)
        _ = s.handle(open(apps, ["Commands", "Applications"]), at: 200)
        #expect(s.handle(.run(binding, frontApp: nil), at: 400) == [])
        #expect(s.nextDeadline == nil && !s.isVisible)
    }

    @Test("Every key, including Back, restarts the delay")
    func restarts() {
        var s = schedule(delay: 500)
        _ = s.handle(open(leader), at: 0)
        _ = s.handle(open(apps, ["Commands", "Applications"]), at: 400)
        #expect(s.tick(at: 500) == [])
        // Back to the leader's menu at 800 restarts it again.
        _ = s.handle(open(leader), at: 800)
        #expect(s.tick(at: 1_200) == [])
        #expect(s.tick(at: 1_300) == [shown(leader)])
    }

    @Test("Once shown, the Guide stays until the sequence ends, updating in place")
    func stays() {
        var s = schedule(delay: 500)
        _ = s.handle(open(leader), at: 0)
        _ = s.tick(at: 500)
        #expect(s.handle(open(apps, ["Commands", "Applications"]), at: 600) == [shown(apps, ["Commands", "Applications"])])
        #expect(s.tick(at: 100_000) == [])
        #expect(s.handle(.cancelled, at: 100_001) == [.hide])
    }
}

@Suite("Guide timeout (S-017)")
struct GuideTimeoutTests {
    @Test("The timeout runs only while the Guide is visible")
    func onlyVisible() {
        var s = schedule(delay: 500, timeout: 1_000)
        _ = s.handle(open(leader), at: 0)
        // While waiting for the delay there's no timeout.
        #expect(s.nextDeadline == 500)
        _ = s.tick(at: 500)
        #expect(s.nextDeadline == 1_500)
        #expect(s.tick(at: 1_500) == [.hide, .endSequence])
        #expect(!s.isVisible && s.nextDeadline == nil)
    }

    @Test("Every key press restarts the timeout")
    func restarts() {
        var s = schedule(timeout: 1_000)
        _ = s.handle(open(leader), at: 0)
        _ = s.handle(open(apps, ["Commands", "Applications"]), at: 900)
        #expect(s.tick(at: 1_000) == [])
        _ = s.handle(.unbound(path: ["Commands", "Applications"]), at: 1_800)
        #expect(s.tick(at: 2_700) == [])
        #expect(s.tick(at: 2_800) == [.hide, .endSequence])
    }

    @Test("When showHud is false, the timeout never fires")
    func noHud() {
        var s = schedule(timeout: 1_000, showHud: false)
        _ = s.handle(open(leader), at: 0)
        #expect(s.nextDeadline == nil)
        #expect(s.tick(at: 10_000) == [])
    }

    @Test("A timeout of 0 is off")
    func off() {
        var s = schedule(timeout: 0)
        _ = s.handle(open(leader), at: 0)
        #expect(s.nextDeadline == nil)
    }
}

@Suite("Unbound key feedback (S-018)")
struct GuideErrorTests {
    @Test("An unbound key flashes and beeps, and the Guide stays")
    func feedback() {
        var s = schedule()
        _ = s.handle(open(leader), at: 0)
        #expect(s.handle(.unbound(path: ["Commands"]), at: 10) == [.bell, .flash])
        #expect(s.isVisible)
    }

    @Test("errorBell and errorFlash turn each part off")
    func settings() {
        var quiet = schedule(bell: false)
        _ = quiet.handle(open(leader), at: 0)
        #expect(quiet.handle(.unbound(path: ["Commands"]), at: 10) == [.flash])
        var still = schedule(flash: false)
        _ = still.handle(open(leader), at: 0)
        #expect(still.handle(.unbound(path: ["Commands"]), at: 10) == [.bell])
    }

    @Test("If the Guide was still waiting for its delay, it appears at once")
    func revealsEarly() {
        var s = schedule(delay: 500)
        _ = s.handle(open(leader), at: 0)
        #expect(s.handle(.unbound(path: ["Commands"]), at: 100) == [.bell, shown(leader), .flash])
        #expect(s.isVisible && s.nextDeadline == nil)
    }

    @Test("An unavailable Context Aware binding gets the same feedback")
    func unavailable() {
        var s = schedule()
        _ = s.handle(open(leader), at: 0)
        #expect(s.handle(.unavailable(binding, path: ["Commands"]), at: 10) == [.bell, .flash])
    }
}

@Suite("No Guide at all (S-021)")
struct GuideHiddenTests {
    @Test("With showHud false, nothing is ever shown, and errors still beep")
    func never() {
        var s = schedule(delay: 0, showHud: false)
        #expect(s.handle(open(leader), at: 0) == [])
        #expect(s.handle(.unbound(path: ["Commands"]), at: 1) == [.bell])
        #expect(s.handle(.run(binding, frontApp: nil), at: 2) == [])
        #expect(!s.isVisible)
    }
}
