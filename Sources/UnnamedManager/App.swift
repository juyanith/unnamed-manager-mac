import AppKit
import SwiftUI

// UnnamedManager
//   UnnamedManager                      the app (menu bar only until a window opens)
//   APP_STORE=<file> UnnamedManager     use another config file (tests, experiments)
//   APP_SNAPSHOT=<dir> UnnamedManager   save a PNG of every Bindings page and Settings in light and dark mode, then quit
//   UnnamedManager --selftest           run the self-test against a /tmp config and quit with 0 or 1 (tools/selftest.sh)
//   APP_GRID=1 UnnamedManager           draw the grid and the layout probes over the window

@main
struct UnnamedManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    /// Snapshots and the self-test need the window open at launch. Normal
    /// launches stay in the menu bar until you choose Edit Bindings…
    private static var opensWindowAtLaunch: Bool {
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

        // The main window: your bindings, actions and contexts. Its title
        // follows the page (DESIGN.md, Information architecture).
        Window("Bindings", id: WindowID.bindings) {
            ContentView()
                .environment(model)
                .themed()
                .countsAsOpenWindow(model)
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: Layout.windowMin.width, minHeight: Layout.windowMin.height)
        }
        .defaultSize(Layout.windowDefault)
        .defaultLaunchBehavior(Self.opensWindowAtLaunch ? .presented : .suppressed)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            EditorCommands(model: model)
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

        Settings {
            SettingsView()
                .environment(model)
                .themed()
                .countsAsOpenWindow(model)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let bindings = "bindings"
    static let welcome = "welcome"
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
