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

    /// S-092: Recent Windows against fake windows: what it lists, choosing
    /// brings windows back, and two quick choices go back and forth.
    static func recentChecks(_ model: AppModel) async {
        let store = model.store
        let launcher = model.launcher
        let good = try? String(contentsOf: store.url, encoding: .utf8)
        try? Data("""
        { "version": 1, "runtime": { "hudDelayMs": 0 }, "entries": [
          { "keys": "CAG+F18", "title": "Recent Windows", "hold": true, "list": { "type": "windows.recent" } },
          { "keys": "CAG+F17", "title": "Here", "hold": true, "list": { "type": "windows.recent", "minimized": false, "hidden": false, "spaces": "current" } }
        ] }
        """.utf8).write(to: store.url)
        store.reload()
        let realWindows = launcher.windows, realHeld = launcher.heldModifiers
        let cag: Modifiers = [.control, .option, .command]
        let held = Held(cag)
        launcher.heldModifiers = { held.value }
        let fake = FakeWindowSystem()
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        fake.windows = [
            "A": .init(frame: frame, pid: 1, app: "com.apple.Notes", title: "Shopping"),
            "B": .init(frame: frame, pid: 2, app: "com.apple.Safari", title: "Apple"),
            "C": .init(frame: frame, isMinimized: true, pid: 3, app: "com.apple.TextEdit", title: "Draft"),
            "D": .init(frame: frame, pid: 4, app: "com.apple.Terminal", title: "", isHidden: true),
            "E": .init(frame: frame, pid: 5, app: "com.apple.Mail", space: 2, title: "Inbox"),
        ]
        launcher.windows = WindowControl(system: fake)
        // Each had focus once, E on Space 2; A is in front.
        for id in ["E", "B", "A"] { fake.click(id) }

        func open(_ key: KeyName = .f18) async {
            held.value = cag
            launcher.handleForTesting(.down(keyCode: key.keyCode!, modifiers: cag, isRepeat: false))
            try? await Task.sleep(for: .milliseconds(50))
        }
        func letGo() async {
            held.value = []
            launcher.handleForTesting(.flags([]))
            try? await Task.sleep(for: .milliseconds(100))
        }

        await open()
        let rows = launcher.guide.content?.rows ?? []
        check("S-092 Recent Windows lists the history first, then the others, without the window in front",
              rows.map(\.title) == ["Shopping", "Apple", "Inbox", "Draft", "Terminal"], "\(rows.map(\.title))")
        check("S-092 Cancel shows the window in front, with its app's icon",
              rows.first?.isCancel == true && rows.first?.icon == .app("com.apple.Notes"))
        check("S-092 items have keys 1 to 9, and their apps' icons",
              rows.dropFirst().map(\.key) == ["1", "2", "3", "4"] && rows[1].icon == .app("com.apple.Safari"))
        check("S-092 the Guide marks another Space, minimized and hidden, and a window with no title shows its app",
              rows[2].note == "on another Space" && rows[3].note == "minimized" && rows[4].note == "hidden" && rows[4].title == "Terminal",
              "\(rows.map(\.note))")
        launcher.handleForTesting(.down(keyCode: KeyName.d3.keyCode!, modifiers: cag, isRepeat: false))
        await letGo()
        check("S-092 choosing a minimized window brings it back and focuses it",
              fake.restored == ["C"] && fake.windows["C"]?.isMinimized == false && fake.focused == "C")

        // No focus change is reported: the history alone must go back and forth.
        await open()
        await letGo()
        let first = fake.focused
        await open()
        await letGo()
        check("S-092 two quick choices go back, then right back again", first == "A" && fake.focused == "C",
              "\(String(describing: first)), \(String(describing: fake.focused))")

        await open()
        let terminal = launcher.guide.content?.rows.firstIndex { $0.title == "Terminal" } ?? 0
        launcher.handleForTesting(.down(keyCode: KeyName.itemKeys[terminal - 1].keyCode!, modifiers: cag, isRepeat: false))
        await letGo()
        check("S-092 choosing a hidden app's window shows the app", fake.windows["D"]?.isHidden == false && fake.focused == "D")

        fake.windows["B"]?.isMinimized = true
        fake.windows["C"]?.isHidden = true
        await open(.f17)
        check("S-092 a list's filters leave out minimized, hidden and other-Space windows",
              launcher.guide.content?.rows.dropFirst().map(\.title) == ["Shopping"], "\(launcher.guide.content?.rows.map(\.title) ?? [])")
        // An item's window closes while the list is up.
        fake.windows["A"] = nil
        try? await Task.sleep(for: .milliseconds(400))
        check("S-092 an item whose window closes leaves the list", launcher.guide.content?.rows.contains { $0.title == "Shopping" } == false,
              "\(launcher.guide.content?.rows.map(\.title) ?? [])")
        launcher.handleForTesting(.down(keyCode: KeyName.escape.keyCode!, modifiers: [], isRepeat: false))
        held.value = []
        try? await Task.sleep(for: .milliseconds(300))

        // Only the window in front: only Cancel, and letting go does nothing.
        fake.windows = ["A": .init(frame: frame, pid: 1, app: "com.apple.Notes", title: "Shopping")]
        fake.click("A")
        let restored = fake.restored.count, alerts = launcher.alertsPlayed
        await open()
        check("S-092 with no other window, a held list has only Cancel", launcher.guide.content?.rows.count == 1
              && launcher.guide.content?.highlight == 0)
        await letGo()
        check("S-092 letting go of Cancel does nothing and plays no sound",
              fake.restored.count == restored && launcher.alertsPlayed == alerts && !launcher.sequenceIsHeld)

        launcher.windows = realWindows
        launcher.heldModifiers = realHeld
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
