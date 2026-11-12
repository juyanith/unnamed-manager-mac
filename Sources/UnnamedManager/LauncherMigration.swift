import AppKit
import SwiftUI
import UnnamedManagerKit

/// Coming from Unnamed Launcher (S-058): copy its config in place of the
/// starter config on first launch, and say when it's still running and may
/// take the same keys. This is the one file that names the old app
/// (AppNameTests).
@Observable
final class LauncherMigration {
    static let bundleID = "net.unnamed.launcher"

    /// Where Unnamed Launcher keeps its config. With APP_STORE set, only
    /// APP_LAUNCHER_STORE counts, so tests and snapshots never read the real file.
    static func sourceURL(environment: [String: String], home: URL) -> URL? {
        if let path = environment["APP_LAUNCHER_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard !ConfigLocation.isOverridden(environment: environment) else { return nil }
        return home.appending(path: ".config/unnamed-launcher/config.json")
    }

    /// The offer replaces only a starter config this launch wrote and nobody
    /// has changed since, so it never overwrites a config of yours.
    static func shouldOffer(createdStarter: Bool, current: Data?, sourceExists: Bool) -> Bool {
        createdStarter && sourceExists && current == Data(ConfigLoader.starterJSON.utf8)
    }

    enum State: Equatable {
        case hidden, offer, copied
        case failed(String)
    }

    private(set) var state: State = .hidden
    private(set) var isLauncherRunning = false
    private(set) var source: URL?
    private let store: ConfigStore
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(store: ConfigStore, source: URL?) {
        self.store = store
        self.source = source
    }

    /// Call once the store has started, so it knows whether it wrote the starter.
    func start() {
        let sourceExists = source.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        if Self.shouldOffer(createdStarter: store.createdStarter, current: try? Data(contentsOf: store.url),
                            sourceExists: sourceExists) {
            state = .offer
        }
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    /// Copy Config. Reads the launcher's file and never writes to it.
    func copy() {
        guard let source, state != .copied else { return }
        // The starter may have been edited since launch; then it's yours.
        guard (try? Data(contentsOf: store.url)) == Data(ConfigLoader.starterJSON.utf8) else {
            state = .hidden
            return
        }
        do {
            try store.replace(with: Data(contentsOf: source))
            state = .copied
            log.info("Copied the Unnamed Launcher config from \(source.path, privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("Unable to copy the Unnamed Launcher config: \(error.localizedDescription, privacy: .public)")
        }
    }

    func quitLauncher() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID) {
            app.terminate()
        }
    }

    private func refreshRunning() {
        isLauncherRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Snapshots and the self-test show each state without the real files or apps.
    func show(_ state: State, launcherRunning: Bool, source: URL? = nil) {
        self.state = state
        if let source { self.source = source }
        isLauncherRunning = launcherRunning
    }

    /// The source path with ~ for the home folder, as Welcome shows paths.
    var sourceDisplayPath: String {
        guard let source else { return "" }
        return source.path(percentEncoded: false)
            .replacingOccurrences(of: URL.homeDirectory.path(percentEncoded: false), with: "~/")
    }

    enum Words {
        static let copyTitle = "Copy Your Unnamed Launcher Config"
        static let copyDetail = "Your leaders, bindings, actions and contexts, in place of the starter config."
        static let copyButton = "Copy Config"
        static let runningTitle = "Unnamed Launcher Is Running"
        static let runningDetail = "It may take the same keys. Quit it to use Unnamed Manager alone."
        static let quitButton = "Quit Unnamed Launcher"
        static func copied(_ path: String) -> String { "Copied from \(path)" }
        static func failed(_ reason: String) -> String { "Unable to copy the config: \(reason)" }
    }
}

/// The Welcome window's rows for S-058, above the three setup steps.
struct LauncherMigrationRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let migration = model.migration
        switch migration.state {
        case .hidden:
            EmptyView()
        case .offer, .failed:
            row(symbol: "arrow.down.doc", tint: .secondary, title: LauncherMigration.Words.copyTitle) {
                if case let .failed(reason) = migration.state {
                    Label(LauncherMigration.Words.failed(reason), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Surfaces.warning)
                } else {
                    Text(LauncherMigration.Words.copyDetail).foregroundStyle(.secondary)
                }
            } trailing: {
                Button(LauncherMigration.Words.copyButton) { migration.copy() }
            }
        case .copied:
            row(symbol: "checkmark.circle.fill", tint: Palette.accentText, title: LauncherMigration.Words.copyTitle) {
                Text(LauncherMigration.Words.copied(migration.sourceDisplayPath)).foregroundStyle(.secondary)
            } trailing: {
                EmptyView()
            }
            .accessibilityValue("Copied")
        }
        if migration.isLauncherRunning {
            row(symbol: "exclamationmark.triangle.fill", tint: Surfaces.warning, title: LauncherMigration.Words.runningTitle) {
                Text(LauncherMigration.Words.runningDetail).foregroundStyle(.secondary)
            } trailing: {
                Button(LauncherMigration.Words.quitButton) { migration.quitLauncher() }
            }
        }
    }

    /// Lined up with WelcomeView's steps: symbol column, title, detail, button.
    private func row(symbol: String, tint: Color, title: String, @ViewBuilder detail: () -> some View,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: Space.xxl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(title).font(.headline)
                detail().fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The menu bar menu's section while Unnamed Launcher runs (S-058).
struct LauncherRunningSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.migration.isLauncherRunning {
            Section(LauncherMigration.Words.runningTitle) {
                Text(LauncherMigration.Words.runningDetail)
                Button(LauncherMigration.Words.quitButton) { model.migration.quitLauncher() }
            }
        }
    }
}
