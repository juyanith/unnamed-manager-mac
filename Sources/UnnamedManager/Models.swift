import AppKit
import UnnamedManagerKit

/// The Settings window's tabs, in order (DESIGN.md, Archetype). Snapshot
/// mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, bindings, actions, contexts, windows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .bindings: "Bindings"
        case .actions: "Actions"
        case .contexts: "Contexts"
        case .windows: "Windows"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .bindings: "keyboard"
        case .actions: "bolt"
        case .contexts: "macwindow.on.rectangle"
        case .windows: "rectangle.split.2x1"
        }
    }

    /// The tabs that edit a list beside a form. They fill a resizable
    /// window; the others are a Form that fits its content.
    var isEditor: Bool { self == .bindings || self == .actions || self == .contexts }
}

/// App-wide state that menus and views share.
@Observable
final class AppModel {
    /// The Settings tab on screen. Settings opens on Bindings, then on the
    /// tab you used last.
    var tab: SettingsTab = .bindings

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
    /// The draft every Settings tab edits.
    let editor: BindingsEditor
    /// The selected action and context on their pages.
    var actionSelection: String?
    var contextSelection: String?
    /// The built-in action kinds open on the Help page (S-081).
    var openBuiltIns: Set<String> = []
    /// A built-in action kind for the Help page to scroll to, once.
    var revealBuiltIn: String?

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

    /// Open the Settings window and the Help window. MenuBarIcon sets them,
    /// since only a view can open a SwiftUI window and the menu bar icon is
    /// the one view that's always there.
    var openSettingsWindow: (() -> Void)?
    var openHelpWindow: (() -> Void)?

    /// Settings… in the menu bar menu, and links from Help: the Settings
    /// window on `tab`, in front.
    func showSettings(_ tab: SettingsTab? = nil) {
        if let tab { self.tab = tab }
        openSettingsWindow?()
        bringToFront(WindowID.settings)
    }

    /// Help in the menu bar menu, the Help menu and the Show Help action:
    /// the Help window, in front (S-052, S-053).
    func showHelp() {
        openHelpWindow?()
        bringToFront(WindowID.help)
    }

    /// Brings the app and the window whose identifier starts with `prefix`
    /// in front of other apps' windows: Settings… and Help.
    /// macOS can ignore activate() from a menu bar app, or from a chord
    /// while another app is active, so the window would open behind.
    /// NSWorkspace can bring it forward, as it does apps for Use Application.
    func bringToFront(_ prefix: String) {
        let wasAccessory = NSApp.activationPolicy() != .regular
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Task { @MainActor in
            // An app that was menu bar only takes a moment to become a
            // regular app, and can't be brought forward until it is.
            if wasAccessory { try? await Task.sleep(for: Self.becomesRegular) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // (Accessibility's frontmost attribute reports success and does nothing.)
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(prefix) == true }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private static let becomesRegular = Duration.milliseconds(200)

    /// Shows one kind's built-in actions on the Help page (S-081).
    func showBuiltIns(_ kind: String) {
        openBuiltIns.insert(kind)
        revealBuiltIn = kind
        showHelp()
    }

    /// Shows an action on the Actions page.
    func showAction(_ id: String) {
        actionSelection = id
        tab = .actions
    }
}

enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        ConfigLocation.isOverridden(environment: ProcessInfo.processInfo.environment)
    }
}
