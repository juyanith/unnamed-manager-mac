import AppKit
import OSLog
import UnnamedManagerKit

nonisolated let log = Logger(subsystem: "net.unnamed.manager", category: "launcher")

/// The config file: the one owner of reading, writing and watching it
/// (S-001, S-008, S-033). A reload with errors keeps the last valid config
/// running, and a save with errors is refused.
@Observable
final class ConfigStore {
    let url: URL
    /// The config in use, or nil when no valid config has loaded yet.
    private(set) var loaded: LoadedConfig?
    /// The last valid file as an editable document, for the Bindings window.
    private(set) var document: ConfigDocument?
    /// Errors from the last load. Empty when it succeeded.
    private(set) var errors: [ConfigIssue] = []
    /// When the config in use was loaded.
    private(set) var loadedAt: Date?
    /// True after this launch wrote the starter config ("Created config file").
    private(set) var createdStarter = false
    /// Bumped on every load from disk, so open windows know to refresh.
    private(set) var revision = 0

    /// Called after every successful load, so the engine can swap configs.
    var onLoad: ((LoadedConfig) -> Void)?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    /// The file itself, for programs that rewrite it in place (no folder event).
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    /// The bytes last read or written, so our own saves don't reload twice.
    @ObservationIgnored private var lastData: Data?

    init(url: URL) {
        self.url = url
    }

    /// Writes the starter config if there is no file, loads it, and starts
    /// watching for changes made outside the app.
    /// `seed` replaces the starter, for snapshots.
    func start(seed: String? = nil) {
        do {
            if let seed, !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try Data(seed.utf8).write(to: url)
            }
            createdStarter = try ConfigLoader.writeStarterIfMissing(at: url)
            try ConfigLoader.writeSchema(nextTo: url)
            if createdStarter { log.info("Wrote the starter config to \(self.url.path, privacy: .public)") }
        } catch {
            log.error("Unable to write the starter config: \(error.localizedDescription, privacy: .public)")
        }
        reload()
        watch()
    }

    /// Reads the file again and uses it if it's valid (Reload Config).
    func reload() {
        guard let data = try? Data(contentsOf: url) else {
            errors = [ConfigIssue(.error, "Unable to read \(url.path).")]
            return
        }
        lastData = data
        revision += 1
        switch ConfigLoader.load(data) {
        case let .success(config):
            loaded = config
            document = try? ConfigDocument(data: data)
            errors = []
            loadedAt = .now
            for warning in config.warnings { log.notice("Config warning: \(warning.message, privacy: .public)") }
            onLoad?(config)
        case let .failure(failure):
            errors = failure.issues
            for issue in failure.issues { log.error("Config error: \(issue.message, privacy: .public)") }
        }
    }

    /// Writes new bytes over the file, atomically, and loads them, valid or
    /// not, as if they'd been edited outside the app (S-058).
    func replace(with data: Data) throws {
        try data.write(to: url, options: .atomic)
        watchFile()  // the atomic write replaced the file
        createdStarter = false
        reload()
    }

    /// Writes a document if it's valid, atomically, and starts using it.
    /// A document with errors is refused and the file isn't touched.
    @discardableResult
    func save(_ document: ConfigDocument) -> Result<Void, ConfigErrors> {
        let config: LoadedConfig
        switch document.validate() {
        case let .success(valid): config = valid
        case let .failure(failure): return .failure(failure)
        }
        let data = document.data()
        guard data != lastData else { return .success(()) }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return .failure(ConfigErrors(issues: [ConfigIssue(.error, "Unable to save \(url.path): \(error.localizedDescription)")]))
        }
        lastData = data
        watchFile()  // the atomic write replaced the file
        loaded = config
        self.document = document
        errors = []
        loadedAt = .now
        onLoad?(config)
        log.info("Saved the config")
        return .success(())
    }

    /// Watches the file's folder, because editors and chezmoi replace the
    /// file rather than writing into it (S-033, S-035), and the file itself,
    /// for programs that write into it.
    private func watch() {
        watchFile()
        let folder = url.deletingLastPathComponent()
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fileMaybeChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Watches the file now at the path. A replaced file is a new file, so
    /// this runs again after every change and every save.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fileMaybeChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatcher = source
    }

    @ObservationIgnored private var pendingCheck: Task<Void, Never>?

    /// Waits a moment for the writer to finish, then reloads if the bytes changed.
    private func fileMaybeChanged() {
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            watchFile()
            guard let data = try? Data(contentsOf: url), data != lastData else { return }
            log.info("The config file changed on disk; reloading")
            reload()
        }
    }

    /// Opens the file in the default editor for JSON.
    func openFile() {
        NSWorkspace.shared.open(url)
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
