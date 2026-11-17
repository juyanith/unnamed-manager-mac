import AppKit
import SwiftUI

// UnnamedManager
//   UnnamedManager                      the app (menu bar only until a window opens)
//   APP_STORE=<file> UnnamedManager     use another config file (tests, experiments)
//   APP_SNAPSHOT=<dir> UnnamedManager   save a PNG of every Settings tab and Help in light and dark mode, then quit
//   UnnamedManager --selftest           run the self-test against a /tmp config and quit with 0 or 1 (tools/selftest.sh)
//   APP_GRID=1 UnnamedManager           draw the grid and the layout probes over the window

@main
struct UnnamedManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    /// Snapshots and the self-test need Settings open at launch. Normal
    /// launches stay in the menu bar until you choose Settings…
    static var opensWindowAtLaunch: Bool {
        SelfTest.requested || !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty
    }

    /// The welcome window opens on its own until permissions are granted
    /// and a sequence has run. Never in snapshots or the self-test.
    private static var showsWelcome: Bool {
        guard !opensWindowAtLaunch else { return false }
        let ran = UserDefaults.standard.bool(forKey: "ranSequence")
        return !(ran && Permission.missing.isEmpty)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environment(model)
        } label: {
            MenuBarIcon()
                .environment(model)
        }

        // First-run setup (S-040). Opens at launch until setup is done.
        Window("Welcome to Unnamed Manager", id: WindowID.welcome) {
            WelcomeView()
                .environment(model)
                .themed()
                .countsAsOpenWindow(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Self.showsWelcome ? .presented : .suppressed)

        // Your bindings, actions and contexts, and the preferences, a tab
        // each (DESIGN.md, Archetype; S-085).
        Settings {
            SettingsWindow()
                .environment(model)
                .themed()
                .countsAsOpenWindow(model)
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .windowResizability(.contentSize)
        .commands {
            EditorCommands(model: model)
        }

        // Help isn't a setting, so it has a window of its own (S-052).
        Window("Unnamed Manager Help", id: WindowID.help) {
            HelpPage()
                .environment(model)
                .themed()
                .countsAsOpenWindow(model)
                .noInitialFocus()
                .frame(minWidth: Layout.helpMin.width, minHeight: Layout.helpMin.height)
        }
        .defaultSize(Layout.helpDefault)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let help = "help"
    /// The identifier SwiftUI gives the Settings scene's window.
    static let settings = "com_apple_SwiftUI_Settings_window"
}

extension View {
    /// Counts this window as open, so the app shows a main menu while it is.
    func countsAsOpenWindow(_ model: AppModel) -> some View {
        onAppear { model.openWindows += 1 }
            .onDisappear { model.openWindows -= 1 }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app: no Dock icon and no main menu until a window opens.
        if NSApp.windows.allSatisfy({ !$0.isVisible }) { NSApp.setActivationPolicy(.accessory) }
    }

    /// Closing the last window leaves the app running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Removes the tap before quitting (S-009). The self-test's result
    /// becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.current?.launcher.stop()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
