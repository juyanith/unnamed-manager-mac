import AppKit
import UnnamedManagerKit

/// Carries out an ActionPlan. The seam between the launcher and the world:
/// SystemPerformer does it for real, RecordingPerformer (self-test) only
/// writes it down.
protocol ActionPerformer {
    func perform(_ plan: ActionPlan) async throws(PlanError)
}

/// A family's own step (`ActionPlan.custom`, S-060), carried out by the
/// step itself. A family conforms its step type in its own app file.
protocol PerformableStep: ActionStep {
    func perform(in context: StepContext) async throws(PlanError)
}

/// What a family's step can use, so the self-test can hand it fakes.
struct StepContext {
    /// The windows on screen, and what Maximize remembers (S-062).
    var windows: WindowControl
}

/// Runs a binding's action (S-006, S-010 to S-014).
struct ActionRunner {
    var performer: any ActionPerformer = SystemPerformer()
    var home: URL = .homeDirectory

    func run(_ action: Config.Action, id: String) async throws(PlanError) {
        let plan = try ActionPlanner.plan(action, home: home)
        try await performer.perform(plan)
    }
}

/// Does each plan with NSWorkspace.
struct SystemPerformer: ActionPerformer {
    var context = StepContext(windows: WindowControl(system: AXWindowSystem(), gap: {
        AppModel.current?.store.loaded?.config.windows.gap ?? Config.Windows().gap
    }))

    func perform(_ plan: ActionPlan) async throws(PlanError) {
        switch plan {
        case let .openApp(bundleId):
            try await openApp(bundleId)
        case let .focusApp(bundleId):
            try await focusApp(bundleId)
        case let .startApp(bundleId):
            try await openApp(bundleId, newCopy: true)
        case let .open(url):
            try await open(url)
        case .nothing:
            return
        case .showHelp:
            AppModel.current?.showHelp()
        case let .spawn(program, arguments, cwd, env):
            try spawn(program, arguments: arguments, cwd: cwd, env: env)
        case let .send(chords):
            try SendShortcut.post(chords)
        case let .custom(custom):
            guard let step = custom.step as? any PerformableStep else {
                throw PlanError("This kind of action can't run on this Mac yet.")
            }
            try await step.perform(in: context)
        }
    }

    /// Starts a program directly, with no shell, and doesn't wait for it
    /// (S-011). A name without a slash is looked up in PATH plus the usual
    /// Homebrew and user folders.
    private func spawn(_ program: String, arguments: [String], cwd: URL, env: [String: String]) throws(PlanError) {
        let environment = ProcessInfo.processInfo.environment
        let searchPath = ActionPlanner.searchPath(environmentPath: environment["PATH"], home: .homeDirectory)
        guard let path = ActionPlanner.locate(program, searchPath: searchPath,
                                              isExecutable: FileManager.default.isExecutableFile(atPath:)) else {
            throw PlanError(program.contains("/") ? "Couldn't run \(program): it doesn't exist or can't be run."
                                                  : "Couldn't run \(program): it isn't in PATH.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var merged = environment
        merged["PATH"] = searchPath.joined(separator: ":")
        merged.merge(env) { _, new in new }
        process.environment = merged
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw PlanError("Couldn't run \(program): \(error.localizedDescription)")
        }
        log.info("Started \(path, privacy: .public)")
    }

    /// Brings the app forward if it's running, otherwise launches it. Going
    /// through NSWorkspace activates it even though this app isn't active.
    /// With `newCopy`, starts another copy even if one is running (Start).
    /// Otherwise a running app comes back to its last focused window (S-047).
    private func openApp(_ bundleId: String, newCopy: Bool = false) async throws(PlanError) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw PlanError("Couldn't open \(bundleId): not installed.")
        }
        if !newCopy, let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            AXWindowSystem.raiseLastFocused(pid: running.processIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = newCopy
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw PlanError("Couldn't open \(bundleId): \(error.localizedDescription)")
        }
    }

    /// Brings the app forward only if it's running (Focus, S-046).
    private func focusApp(_ bundleId: String) async throws(PlanError) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
                .map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "") }
            throw PlanError("\(name ?? bundleId) isn't running.")
        }
        AXWindowSystem.raiseLastFocused(pid: running.processIdentifier)
        guard let url = running.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw PlanError("Couldn't focus \(bundleId): \(error.localizedDescription)")
        }
    }

    /// Opens a file, folder or URL in its default app (S-010).
    private func open(_ url: URL) async throws(PlanError) {
        let name = url.isFileURL ? url.path(percentEncoded: false) : url.absoluteString
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            throw PlanError("Couldn't open \(name): it doesn't exist.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        } catch {
            throw PlanError("Couldn't open \(name): \(error.localizedDescription)")
        }
    }
}

/// Writes plans down instead of doing them, for the self-test.
final class RecordingPerformer: ActionPerformer {
    private(set) var plans: [ActionPlan] = []

    func perform(_ plan: ActionPlan) async throws(PlanError) {
        plans.append(plan)
    }
}
