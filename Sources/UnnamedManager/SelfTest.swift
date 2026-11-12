import AppKit
import OSLog
import Synchronization
import UnnamedManagerKit

/// Self-test for agents: runs the app's real functions against a test config,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/UnnamedManager-self.json build/UnnamedManager.app/Contents/MacOS/UnnamedManager --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0
    /// The Bindings window's task starts the run, and S-053 closes and
    /// reopens that window, so the run must start only once.
    private static var started = false

    static func runIfRequested(model: AppModel) {
        guard requested, !started else { return }
        started = true
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            check("the config file is the /tmp override", model.configURL.path.hasPrefix("/tmp/"))
            check("the app is a menu bar app (LSUIElement)", Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
            check("an open window gives the app a main menu", NSApp.activationPolicy() == .regular)
            check("the Bindings window opens on Bindings", model.sidebar == .bindings)
            model.sidebar = .contexts
            check("the Bindings window can switch pages", model.sidebar == .contexts)

            await configChecks(model)
            await guideChecks(model)
            await actionChecks()
            await failureChecks(model)
            await editorChecks(model)
            systemChecks(model)
            await polishChecks(model)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// True when this run's log has a line containing `text`.
    static func logContains(_ text: String) -> Bool {
        (try? OSLogStore(scope: .currentProcessIdentifier))
            .flatMap { try? $0.getEntries(at: $0.position(timeIntervalSinceLatestBoot: 0)) }?  // grid: ok OSLogStore, not a view
            .compactMap { $0 as? OSLogEntryLog }
            .contains { $0.subsystem == "net.unnamed.manager" && $0.composedMessage.contains(text) } ?? false
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
