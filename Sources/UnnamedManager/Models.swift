import AppKit
import UnnamedManagerKit

/// The Bindings window's sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case bindings, actions, contexts, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bindings: "Bindings"
        case .actions: "Actions"
        case .contexts: "Contexts"
        case .help: "Help"
        }
    }

    var symbol: String {
        switch self {
        case .bindings: "keyboard"
        case .actions: "bolt"
        case .contexts: "macwindow.on.rectangle"
        case .help: "questionmark.circle"
        }
    }

    /// What the empty page says until its story is built.
    var emptyMessage: String {
        switch self {
        case .bindings: "Leaders, menus and bindings from the config file appear here."
        case .actions: "Actions that bindings run appear here."
        case .contexts: "Sets of apps that Context Aware checks appear here."
        case .help: "Your leaders and direct bindings, and how sequences work."
        }
    }
}

/// App-wide state that menus and views share.
@Observable
final class AppModel {
    var sidebar: SidebarItem? = .bindings

    /// How many of the app's windows are open. While any is, the app is a
    /// regular app with a main menu (Edit > Undo, Window); otherwise it lives
    /// only in the menu bar (DESIGN.md, Archetype).
    var openWindows = 0 {
        didSet {
            NSApp.setActivationPolicy(openWindows > 0 ? .regular : .accessory)
        }
    }

    /// The config file. Tests and snapshots point APP_STORE at a file in /tmp.
    let configURL = ConfigLocation.url(environment: ProcessInfo.processInfo.environment,
                                       home: URL.homeDirectory)
    let store: ConfigStore
    let launcher: Launcher
    /// Copying the old app's config, and noticing it running (S-058).
    let migration: LauncherMigration
    /// The draft the Bindings window and Settings edit.
    let editor: BindingsEditor
    /// The selected action and context on their pages.
    var actionSelection: String?
    var contextSelection: String?

    /// The one model, for the app delegate.
    private(set) static weak var current: AppModel?

    init() {
        store = ConfigStore(url: configURL)
        launcher = Launcher(store: store)
        // Snapshots and the self-test never capture the real keyboard.
        let isSnapshot = !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty
        // Snapshots show the sample config, so every page has content.
        launcher.start(captureKeys: !SelfTest.requested && !isSnapshot, seed: isSnapshot ? SeedData.fixtureJSON : nil)
        migration = LauncherMigration(store: store,
                                      source: LauncherMigration.sourceURL(environment: ProcessInfo.processInfo.environment,
                                                                          home: URL.homeDirectory))
        migration.start()
        editor = BindingsEditor(store: store)
        editor.onRecordingChange = { [launcher] in launcher.setRecording($0) }
        Self.current = self
    }

    /// Opens the Bindings window. MenuBarIcon sets it, since only a view
    /// can open a SwiftUI window and the menu bar icon is the one view
    /// that's always there.
    var openBindingsWindow: (() -> Void)?

    /// Help in the menu bar menu and the Show Help action: the Help page, in front (S-052, S-053).
    func showHelp() {
        sidebar = .help
        openBindingsWindow?()
        // A chord doesn't make this app active, and macOS ignores activate()
        // from an app in the background, so the window would open behind.
        // NSWorkspace can bring it forward, as it does apps for Use Application.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // (Accessibility's frontmost attribute reports success and does nothing.)
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.bindings) == true }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Shows an action on the Actions page.
    func showAction(_ id: String) {
        actionSelection = id
        sidebar = .actions
    }
}

enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        ConfigLocation.isOverridden(environment: ProcessInfo.processInfo.environment)
    }
}
