import AppKit
import UnnamedManagerKit

/// Self-test checks for M12: held menus.
extension SelfTest {
    /// S-090: a held menu whose key-up never reached the tap still chooses,
    /// from the modifiers held, within 200 ms.
    static func heldChecks(_ model: AppModel) async {
        let store = model.store
        let launcher = model.launcher
        let good = try? String(contentsOf: store.url, encoding: .utf8)
        try? Data("""
        { "version": 1, "entries": [
          { "keys": "CAG+F19", "title": "Held", "hold": true },
          { "keys": "CAG+F19 N", "title": "Nothing", "action": "noop" }
        ] }
        """.utf8).write(to: store.url)
        store.reload()

        let real = launcher.heldModifiers
        let cag: Modifiers = [.control, .option, .command]
        let held = Held(cag)
        launcher.heldModifiers = { held.value }
        launcher.handleForTesting(.down(keyCode: KeyName.f19.keyCode!, modifiers: cag, isRepeat: false))
        check("S-090 a held leader opens its menu held", launcher.sequenceIsHeld)
        try? await Task.sleep(for: .milliseconds(250))
        check("S-090 a held menu stays open while its modifiers are held", launcher.sequenceIsHeld)

        // The key-up is lost, as when macOS turns the tap off: only the
        // modifiers held say it happened.
        held.value = []
        let clock = ContinuousClock()
        let start = clock.now
        while launcher.sequenceIsHeld, clock.now - start < .milliseconds(500) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let took = clock.now - start
        check("S-090 a missed key-up chooses within 200 ms", !launcher.sequenceIsHeld && took < .milliseconds(200), "\(took)")
        check("S-090 a missed key-up is logged", logContains("key-up was missed"))

        launcher.heldModifiers = real
        try? good?.write(to: store.url, atomically: true, encoding: .utf8)
        store.reload()
    }

    /// The modifiers the fake keyboard holds, changed while the watch reads them.
    @MainActor private final class Held {
        var value: Modifiers
        init(_ value: Modifiers) { self.value = value }
    }
}
