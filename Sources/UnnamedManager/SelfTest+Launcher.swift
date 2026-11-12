import AppKit
import OSLog
import Synchronization
import UnnamedManagerKit

/// Self-test checks for M1 to M3: config, Guide, actions, failures.
extension SelfTest {
    /// S-001, S-008, S-009: the starter config, reload with errors, Enabled.
    static func configChecks(_ model: AppModel) async {
        let store = model.store
        let launcher = model.launcher
        // tools/selftest.sh deletes the file first, so launch wrote the starter.
        check("S-001 a missing config file gets the starter config", store.createdStarter
              && store.loaded?.leaders.first?.children.map(\.title) == ["Finder", "Terminal"])
        check("S-002 snapshots and self-tests install no event tap", !launcher.isCapturing)
        check("S-051 a release's version line is the version alone",
              AppVersion.line(version: "0.1.3", source: "") == "Version 0.1.3")
        check("S-051 a local build's version line names its branch and commit",
              AppVersion.line(version: "0.1", source: "main, aa45720") == "Version 0.1 (main, aa45720)")
        check("S-051 this build has a version line", AppVersion.line.hasPrefix("Version 0."), AppVersion.line)

        let good = try? String(contentsOf: store.url, encoding: .utf8)
        try? Data(#"{ "version": 1, "entries": [{ "keys": "Hyper+Spcae", "title": "C" }] }"#.utf8).write(to: store.url)
        store.reload()
        check("S-008 a reload with errors keeps the last valid config",
              store.loaded?.leaders.first?.title == "Commands" && !store.errors.isEmpty)
        let broken = MenuBarStatus(launcher: launcher, store: store)
        check("S-008 a config error shows in the menu with a warning icon",
              broken.icon == .warning && broken.firstError?.contains("Hyper+Spcae") == true, broken.firstError ?? "no error")
        try? good?.write(to: store.url, atomically: true, encoding: .utf8)
        store.reload()
        let fixed = MenuBarStatus(launcher: launcher, store: store)
        check("S-008 a fixed file reloads and clears the error", store.errors.isEmpty && fixed.firstError == nil)
        check("S-008 the line under the version says when the config loaded",
              fixed.configLine?.hasPrefix("Config loaded at") == true || fixed.configLine == "Created config file",
              fixed.configLine ?? "nil")

        // S-033: saving. A valid edit is written atomically; an invalid one is refused.
        if var document = store.document {
            document.setTitle(KeySequence(parsing: "Hyper+Space F")!, "Files")
            let saved = store.save(document)
            let text = (try? String(contentsOf: store.url, encoding: .utf8)) ?? ""
            check("S-033 a valid edit is saved to the file", (try? saved.get()) != nil && text.contains(#""title": "Files""#))
            var broken = document
            broken.setAction(KeySequence(parsing: "Hyper+Space F")!, "no-such-action")
            let refused = store.save(broken)
            let after = (try? String(contentsOf: store.url, encoding: .utf8)) ?? ""
            check("S-033 an invalid edit is refused and the file isn't changed", (try? refused.get()) == nil && after == text)

            // Another program changes the file: the store reloads within a second.
            let revision = store.revision
            try? text.replacingOccurrences(of: #""title": "Files""#, with: #""title": "Finder""#)
                .write(to: store.url, atomically: true, encoding: .utf8)
            for _ in 0..<30 where store.revision == revision { try? await Task.sleep(for: .milliseconds(100)) }
            check("S-033 a change on disk reloads", store.revision > revision
                  && store.document?.entry(KeySequence(parsing: "Hyper+Space F")!)?.title == "Finder")

            // Rewritten in place (same file, no rename): still reloads, also after the
            // atomic replace above swapped the file for a new one.
            let inPlace = store.revision
            if let handle = try? FileHandle(forWritingTo: store.url),
               let current = try? String(contentsOf: store.url, encoding: .utf8) {
                let changed = current.replacingOccurrences(of: #""title": "Finder""#, with: #""title": "Files""#)
                try? handle.truncate(atOffset: 0)
                try? handle.write(contentsOf: Data(changed.utf8))
                try? handle.close()
            }
            for _ in 0..<30 where store.revision == inPlace { try? await Task.sleep(for: .milliseconds(100)) }
            check("S-033 a file rewritten in place reloads", store.revision > inPlace
                  && store.document?.entry(KeySequence(parsing: "Hyper+Space F")!)?.title == "Files")
        } else {
            check("S-033 the config loads as a document", false)
        }

        launcher.isEnabled = false
        let off = MenuBarStatus(launcher: launcher, store: store)
        check("S-009 turning Enabled off dims the icon and says so",
              off.icon == .off && off.statusLine == "Not capturing leaders" && !launcher.isCapturing)
        check("S-009 the off state is in the VoiceOver label", off.accessibilityLabel == "Unnamed Manager, off")
        launcher.isEnabled = true
    }

    /// S-005: the Guide shows the path and rows, and never takes focus.
    static func guideChecks(_ model: AppModel) async {
        let content = SeedData.guideContent
        check("S-005 the Guide lists the leader's keys in file order",
              content.rows.map(\.key) == ["Space", "E", "B", "A", "N", "S", "L", "F", "W"])
        let addressBar = content.rows.first { $0.key == "L" }
        check("S-013 a Context Aware binding with nothing for the app in front is dimmed",
              addressBar?.isAvailable == false && addressBar?.note == "not available in Notes"
              && content.rows.first { $0.key == "F" }?.isAvailable == true)
        check("S-005 menus are marked, bindings aren't",
              content.rows.first { $0.key == "A" }?.isMenu == true && content.rows.first { $0.key == "E" }?.isMenu == false)
        check("S-005 the footer shows esc and delete", content.cancelKey == "esc" && content.backKey == "delete")
        let customText = #"{ "version": 1, "runtime": { "cancelKey": "Q", "backKey": "" }, "entries": [{ "keys": "Hyper+Space", "title": "C" }, { "keys": "Hyper+Space E", "title": "E", "action": "n" }], "actions": { "n": { "type": "noop" } } }"#
        if let custom = try? ConfigLoader.load(Data(customText.utf8)).get() {
            let footer = GuideContent(menu: custom.leaders[0], path: ["C"], config: custom, frontApp: nil)
            check("S-022 the footer shows a custom cancel key and hides Back when it's off",
                  footer.cancelKey == "Q" && footer.backKey == nil)
        } else {
            check("S-022 a config with custom keys loads", false)
        }
        let home = SeedData.homeContent
        check("S-050 Home lists every leader and direct binding by group, the current one first",
              home.sections.map(\.title) == ["Hyper", "Meh", "CAG"] && home.rows.map(\.key) == ["Space", "H", "W", "T"]
              && home.columns.count == 1 && !home.dividesColumns, "\(home.sections.map(\.title))")
        let wide = SeedData.wideHomeContent
        let firstColumn = wide.columns.first?.map(\.title)
        let split = Set(wide.columns.flatMap { $0.map(\.title) }).count != wide.sections.count
        check("S-050 a wide Home puts the current group alone first and never splits a group",
              wide.columns.count > 1 && firstColumn == ["Hyper"] && !split && wide.dividesColumns,
              "\(wide.columns.map { $0.map(\.title) })")
        check("S-050 an unavailable direct binding in Home is dimmed",
              wide.rows.first { $0.title == "Address Bar" }?.isAvailable == false)
        let icons = GuideIcons()
        let missingFile = IconSource.file("/tmp/unnamed-manager-no-such-file")
        let web = IconSource.url(URL(string: "https://example.com")!)
        icons.load([.app("com.apple.Terminal"), .app("com.example.not-installed"), .file("/Applications"), missingFile, web])
        icons.load([.app("com.apple.Terminal")])
        check("S-054 an installed app's icon is looked up once and cached",
              icons.icon(for: .app("com.apple.Terminal")) != nil && icons.lookups == 5, "lookups \(icons.lookups)")
        check("S-054 an app that isn't installed gets no icon", icons.icon(for: .app("com.example.not-installed")) == nil)
        check("S-055 a folder that exists gets its Finder icon; a missing file gets none",
              icons.icon(for: .file("/Applications")) != nil && icons.icon(for: missingFile) == nil)
        check("S-055 a URL gets the icon of the app that opens it", icons.icon(for: web) != nil)
        let rows = content.rows
        check("S-054 Use Application rows carry their app; menus and other actions don't",
              rows.first { $0.title == "Editor" }?.icon == .app("dev.zed.Zed")
              && rows.filter { if case .app = $0.icon { true } else { false } }.map(\.title) == ["Editor", "Browser"],
              "\(rows.map(\.icon))")
        icons.load([.menu])
        check("a menu without an icon of its own gets the app's glyph",
              rows.first { $0.title == "Applications" }?.icon == .menu && icons.icon(for: .menu)?.isTemplate == true)
        check("S-055 an Open row carries its file", rows.first { $0.title.hasPrefix("Notes") }?.icon.map {
            if case let .file(path) = $0 { path.hasSuffix("/Documents") } else { false } } == true)
        check("S-054 a column with an icon keeps the icon space on every row; one without has none",
              content.columns.allSatisfy(GuideContent.showsIcons)
              && !GuideContent.showsIcons([GuideContent.Section(rows: rows.filter { $0.icon == nil })]))
        let lookupsBefore = GuideIcons.shared.lookups
        _ = SeedData.homeContent
        check("S-021 a Guide that's never shown makes no panel", !GuideController().hasPanel)
        let front = NSApp.keyWindow
        let guide = model.launcher.guide
        guide.show(content)
        try? await Task.sleep(for: .seconds(0.3))
        check("S-005 the Guide is on screen", guide.isVisible)
        check("S-005 the Guide never becomes the key window",
              !guide.window.canBecomeKey && !guide.window.isKeyWindow && NSApp.keyWindow === front)
        if let screen = GuideController.frontScreen() {
            check("S-019 the Guide is on the screen of the front app's window",
                  screen.frame.contains(guide.window.frame), "\(guide.window.frame) not in \(screen.frame)")
        } else if let main = NSScreen.main {
            // The front app has no window on screen, such as a menu bar app
            // (another copy of this one, when it's running): the main screen.
            check("S-019 with no front window, the Guide is on the main screen",
                  main.frame.contains(guide.window.frame),
                  "front app \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"): \(guide.window.frame) not in \(main.frame)")
        } else {
            check("S-019 the Guide has a screen", false, "no front window and no main screen")
        }
        guide.flash()
        check("S-018 an unbound key flashes the Guide", guide.isFlashing)
        try? await Task.sleep(for: Motion.errorFlashHold + .milliseconds(150))
        check("S-018 the flash goes away by itself", !guide.isFlashing)
        guide.hide()
        try? await Task.sleep(for: .seconds(0.3))
        check("S-007 the Guide hides when the sequence ends", !guide.window.isVisible)
        check("S-054 S-055 showing the Guide looks up no icons", GuideIcons.shared.lookups == lookupsBefore)

        // S-019: top and bottom sit a fifth of the way in from that edge.
        for position in [GuidePlacement.Position.top, .bottom] {
            guide.position = position
            guide.show(content)
            let visible = (GuideController.frontScreen() ?? NSScreen.main!).visibleFrame
            let expected = GuidePlacement.origin(size: guide.window.frame.size, in: visible, position: position)
            check("S-019 \(position.rawValue) puts the Guide where it should be", guide.window.frame.origin == expected,
                  "\(guide.window.frame.origin) vs \(expected)")
            guide.hide()
            try? await Task.sleep(for: .seconds(0.3))
        }
        guide.position = .center

        // S-020: the theme sets the Guide's own appearance.
        guide.theme = "dark"
        check("S-020 a dark theme makes the Guide dark", guide.window.appearance?.name == .darkAqua)
        guide.theme = "light"
        check("S-020 a light theme makes the Guide light", guide.window.appearance?.name == .aqua)
        guide.theme = "system"
        check("S-020 the system theme follows the Mac", guide.window.appearance == nil)
    }

    /// S-006, S-010: Use Application and Open, through the real performer for
    /// failures and the recording one for plans (nothing is launched).
    static func actionChecks() async {
        let system = ActionRunner()
        do throws(PlanError) {
            try await system.run(.application(bundleId: "net.unnamed.not-installed"), id: "missing")
            check("S-006 a missing app is reported", false, "no failure")
        } catch {
            check("S-006 a missing app is reported", error.message == "Couldn't open net.unnamed.not-installed: not installed.", error.message)
        }
        do throws(PlanError) {
            try await system.run(.open(target: "~/net.unnamed.no-such-file"), id: "missing")
            check("S-010 a missing file is reported", false, "no failure")
        } catch {
            check("S-010 a missing file is reported", error.message.hasSuffix("net.unnamed.no-such-file: it doesn't exist."), error.message)
        }

        let recorder = RecordingPerformer()
        let runner = ActionRunner(performer: recorder, home: URL(fileURLWithPath: "/Users/someone"))
        try? await runner.run(.open(target: "~/notes"), id: "notes")
        try? await runner.run(.open(target: "https://example.com/a?b=1"), id: "web")
        check("S-010 file paths and web URLs both open through NSWorkspace", recorder.plans == [
            .open(URL(fileURLWithPath: "/Users/someone/notes")),
            .open(URL(string: "https://example.com/a?b=1")!),
        ], "\(recorder.plans)")

        // S-046: Use Application's modes, and Focus with the app not running.
        try? await runner.run(.application(bundleId: "a.b", mode: .focus), id: "focus")
        try? await runner.run(.application(bundleId: "a.b", mode: .start), id: "start")
        try? await runner.run(.application(bundleId: "a.b"), id: "either")
        check("S-046 Focus, Start and Focus or Start each plan their own way in",
              recorder.plans.suffix(3) == [.focusApp(bundleId: "a.b"), .startApp(bundleId: "a.b"), .openApp(bundleId: "a.b")],
              "\(recorder.plans)")
        do throws(PlanError) {
            try await system.run(.application(bundleId: "net.unnamed.not-installed", mode: .focus), id: "focus")
            check("S-046 Focus on an app that isn't running says so", false, "no failure")
        } catch {
            check("S-046 Focus on an app that isn't running says so", error.message == "net.unnamed.not-installed isn't running.", error.message)
        }
        // S-047: an app that doesn't answer leaves activation to decide, quickly.
        let asked = ContinuousClock.now
        check("S-047 no window to raise for a process that isn't there",
              !WindowRaiser.raiseLastFocused(pid: 999_999) && ContinuousClock.now - asked < .seconds(1))
        let names = Config.Action.types(allowsContextAware: true).map { Config.Action.empty(of: $0).displayName }
        check("S-046 the Type picker is alphabetical",
              names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
              && Set(["Context Aware", "Do Nothing", "Open", "Run Command", "Send Shortcut", "Show Help", "Use Application"])
                  .isSubset(of: names), "\(names)")
        check("S-046 variants offer every type but Context Aware",
              !Config.Action.types(allowsContextAware: false).contains("contextual"))

        // S-011: a real run, through sh only because this check asks for it.
        let marker = "/tmp/UnnamedManager-exec.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let started = ContinuousClock.now
        do throws(PlanError) {
            try await system.run(.exec(command: ["sh", "-c", "pwd > \(marker); echo \"$UL_CHECK\" >> \(marker); sleep 3"],
                                       cwd: nil, env: ["UL_CHECK": "from env"]), id: "exec")
        } catch {
            check("S-011 a command runs", false, error.message)
        }
        check("S-011 the app doesn't wait for a program that starts", ContinuousClock.now - started < .milliseconds(500))
        try? await Task.sleep(for: .seconds(1))
        let lines = ((try? String(contentsOfFile: marker, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let homePath = ActionPlanner.expandTilde("~", home: .homeDirectory)
        check("S-011 cwd defaults to the home folder", lines.first == homePath, "\(lines)")
        check("S-011 env is added to the inherited environment", lines.dropFirst().first == "from env", "\(lines)")
        // S-012: build the events without posting them, so nothing is typed.
        do throws(PlanError) {
            let chords = try ActionPlanner.chords("Primary+F Cmd+K S")
            let events = try SendShortcut.events(for: chords)
            let flags = events.map(\.flags)
            let codes = events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
            check("S-012 each chord sends a key-down and a key-up", events.count == 6
                  && codes == [0x03, 0x03, 0x28, 0x28, 0x01, 0x01], "\(codes)")
            check("S-012 sent events carry only the chord's own modifiers",
                  flags == [.maskCommand, .maskCommand, .maskCommand, .maskCommand, [], []], "\(flags.map(\.rawValue))")
            check("S-012 sent events are marked so the tap lets them through",
                  events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == SendShortcut.marker })
        } catch {
            check("S-012 a shortcut builds its events", false, error.message)
        }
        do throws(PlanError) {
            try await system.run(.exec(command: ["net-unnamed-no-such-program"], cwd: nil, env: [:]), id: "missing")
            check("S-011 a program that can't be found is reported", false, "no failure")
        } catch {
            check("S-011 a program that can't be found is reported",
                  error.message == "Couldn't run net-unnamed-no-such-program: it isn't in PATH.", error.message)
        }
    }

    /// S-015: a failure shows in the Guide for two seconds and is logged.
    static func failureChecks(_ model: AppModel) async {
        let message = "Couldn't open dev.example.missing: not installed."
        model.launcher.report(message, title: "Editor")
        try? await Task.sleep(for: .seconds(0.3))
        let guide = model.launcher.guide
        check("S-015 the Guide shows the failure", guide.isVisible && guide.content?.failure == message)
        try? await Task.sleep(for: Motion.errorMessageHold + .seconds(0.5))
        check("S-015 the failure closes after two seconds", !guide.window.isVisible)
        let logged = (try? OSLogStore(scope: .currentProcessIdentifier))
            .flatMap { try? $0.getEntries(at: $0.position(timeIntervalSinceLatestBoot: 0)) }?  // grid: ok OSLogStore, not a view
            .compactMap { $0 as? OSLogEntryLog }
            .contains { $0.subsystem == "net.unnamed.manager" && $0.composedMessage.contains(message) } ?? false
        check("S-015 the failure is in the log under net.unnamed.manager", logged)
    }
}
