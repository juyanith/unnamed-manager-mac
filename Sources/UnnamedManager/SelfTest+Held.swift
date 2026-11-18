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
        try? Data(heldConfig(delay: 0).utf8).write(to: store.url)
        store.reload()

        let real = launcher.heldModifiers
        let cag: Modifiers = [.control, .option, .command]
        let held = Held(cag)
        launcher.heldModifiers = { held.value }
        func press(_ key: KeyName, _ modifiers: Modifiers = cag) {
            launcher.handleForTesting(.down(keyCode: key.keyCode!, modifiers: modifiers, isRepeat: false))
        }

        // S-091: the Guide follows the highlight.
        let seeded = SeedData.heldContent
        check("S-091 a held menu's Guide starts with Cancel, with no key",
              seeded.rows.first?.isCancel == true && seeded.rows.first?.title == "Cancel" && seeded.rows.count == SeedData.guideContent.rows.count + 1)
        check("S-091 VoiceOver hears the menu and the highlighted item, then only the item",
              seeded.announcement == "Commands, \(seeded.rows[2].title), 2 of \(seeded.rows.count - 1)"
              && seeded.highlightAnnouncement == "\(seeded.rows[2].title), 2 of \(seeded.rows.count - 1)")
        press(.f19)
        try? await Task.sleep(for: .milliseconds(100))
        check("S-091 the Guide shows a held menu with its first item highlighted",
              launcher.guide.isVisible && launcher.guide.content?.highlight == 1, "\(String(describing: launcher.guide.content?.highlight))")
        press(.f19)
        try? await Task.sleep(for: .milliseconds(50))
        check("S-091 the repeat key moves the highlight in the Guide", launcher.guide.content?.highlight == 2)
        press(.f19, cag.union(.shift))
        press(.up)
        try? await Task.sleep(for: .milliseconds(50))
        check("S-091 Shift with the repeat key and Up move it back", launcher.guide.content?.highlight == 0)
        press(.m)
        try? await Task.sleep(for: .milliseconds(50))
        press(.backspace)
        try? await Task.sleep(for: .milliseconds(50))
        check("S-091 Back highlights the menu you came from", launcher.guide.content?.highlight == 2
              && launcher.guide.content?.path == ["Held"])
        launcher.handleForTesting(.flags([]))
        try? await Task.sleep(for: .milliseconds(50))
        check("S-091 a menu chosen by letting go shows as an ordinary menu",
              launcher.guide.isVisible && launcher.guide.content?.highlight == nil && launcher.guide.content?.path == ["Held", "More"])
        press(.escape, [])
        try? await Task.sleep(for: .milliseconds(300))

        // Letting go before the Guide's delay chooses with no Guide.
        try? Data(heldConfig(delay: 400).utf8).write(to: store.url)
        store.reload()
        press(.f19)
        launcher.handleForTesting(.flags([]))
        try? await Task.sleep(for: .milliseconds(600))
        check("S-091 letting go before the delay chooses with the Guide never shown",
              !launcher.sequenceIsHeld && !launcher.guide.isVisible)
        try? Data(heldConfig(delay: 0).utf8).write(to: store.url)
        store.reload()

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

    /// A held leader on CAG+F19, a key no keyboard sends by accident, with
    /// a binding and a menu.
    private static func heldConfig(delay: Int) -> String {
        """
        { "version": 1, "runtime": { "hudDelayMs": \(delay) }, "entries": [
          { "keys": "CAG+F19", "title": "Held", "hold": true },
          { "keys": "CAG+F19 N", "title": "Nothing", "action": "noop" },
          { "keys": "CAG+F19 M", "title": "More" },
          { "keys": "CAG+F19 M X", "title": "Also Nothing", "action": "noop" }
        ] }
        """
    }

    /// The modifiers the fake keyboard holds, changed while the watch reads them.
    @MainActor private final class Held {
        var value: Modifiers
        init(_ value: Modifiers) { self.value = value }
    }
}
