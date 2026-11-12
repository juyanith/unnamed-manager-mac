import Foundation

/// One thing to do in the world, worked out from an action with no side
/// effects (SPEC.md, Actions). The app's ActionPerformer carries it out, so
/// every rule here is unit-tested and the self-test can record plans
/// instead of running them.
public enum ActionPlan: Sendable, Equatable {
    /// Bring the app forward, launching it first if needed.
    case openApp(bundleId: String)
    /// Bring the app forward only if it's already running.
    case focusApp(bundleId: String)
    /// Start a new copy of the app, even if one is running.
    case startApp(bundleId: String)
    /// Open a file, folder or URL with its default app.
    case open(URL)
    /// Start a program directly, with no shell.
    case spawn(program: String, arguments: [String], cwd: URL, env: [String: String])
    /// Press these chords in the app in front, in order.
    case send([Chord])
    /// Do Nothing.
    case nothing
    /// Open the Help page of the Bindings window.
    case showHelp
    /// A family's own step (S-060), carried out by the app's PerformableStep.
    case custom(AnyActionStep)
}

/// Why an action couldn't be planned. The message is shown in the Guide.
public struct PlanError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum ActionPlanner {
    /// The plan for an action. `home` expands a leading `~`.
    public static func plan(_ action: Config.Action, home: URL) throws(PlanError) -> ActionPlan {
        switch action {
        case let .application(bundleId, mode):
            switch mode {
            case .focusOrStart: return .openApp(bundleId: bundleId)
            case .focus: return .focusApp(bundleId: bundleId)
            case .start: return .startApp(bundleId: bundleId)
            }
        case let .open(target):
            return .open(try openURL(target, home: home))
        case let .exec(command, cwd, env):
            guard let program = command.first, !program.isEmpty else {
                throw PlanError("Run Command needs a program as the first item of “command”.")
            }
            let arguments = command.dropFirst().map { expandTilde($0, home: home) }
            let directory = cwd.map { URL(fileURLWithPath: expandTilde($0, home: home), isDirectory: true) } ?? home
            return .spawn(program: expandTilde(program, home: home), arguments: Array(arguments), cwd: directory, env: env)
        case let .send(keys):
            return .send(try chords(keys))
        case .noop:
            return .nothing
        case .help:
            return .showHelp
        case .contextual:
            // Resolve with `ContextResolver` first.
            throw PlanError("Context Aware must be resolved for the app in front first.")
        }
    }

    /// Expands a leading `~` (alone, or followed by `/`) to the home folder.
    /// Nothing else is expanded: no `$VAR`, no globs, no `~user`.
    public static func expandTilde(_ text: String, home: URL) -> String {
        let homePath = home.path(percentEncoded: false).trimmingSuffix("/")
        if text == "~" { return homePath }
        if text.hasPrefix("~/") { return homePath + text.dropFirst() }
        return text
    }

    /// A web URL as is, or a file path (with `~` expanded) as a file URL.
    static func openURL(_ target: String, home: URL) throws(PlanError) -> URL {
        if let url = URL(string: target), let scheme = url.scheme, scheme.count > 1, target.contains(":") {
            return url
        }
        let path = expandTilde(target, home: home)
        guard path.hasPrefix("/") else {
            throw PlanError("Couldn't open “\(target)”: use a full path, a path starting with ~, or a URL.")
        }
        return URL(fileURLWithPath: path)
    }

    /// Chords separated by spaces: "Cmd+K S" is ⌘K then S. `Primary` is ⌘.
    public static func chords(_ keys: String) throws(PlanError) -> [Chord] {
        let tokens = keys.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { throw PlanError("Send Shortcut needs at least one key in “keys”.") }
        var chords: [Chord] = []
        for token in tokens {
            guard let chord = Chord(parsing: token) else {
                throw PlanError("Send Shortcut can't read “\(token)”. Check the spelling of each key and modifier.")
            }
            chords.append(chord)
        }
        return chords
    }

    /// Finds a program by name in `searchPath`, or checks a path as given.
    /// `isExecutable` is injected so tests don't need real files.
    public static func locate(_ program: String, searchPath: [String],
                              isExecutable: (String) -> Bool) -> String? {
        if program.contains("/") { return isExecutable(program) ? program : nil }
        for directory in searchPath where !directory.isEmpty {
            let candidate = directory.trimmingSuffix("/") + "/" + program
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// Where Run Command looks for programs named without a path. Apps
    /// started from the Dock or at login get only the system folders in
    /// PATH, so the usual Homebrew and user folders are added after it.
    public static func searchPath(environmentPath: String?, home: URL) -> [String] {
        var directories = (environmentPath ?? "").split(separator: ":").map(String.init)
        let homePath = home.path(percentEncoded: false).trimmingSuffix("/")
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", homePath + "/.local/bin",
                      "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !directories.contains(extra) {
            directories.append(extra)
        }
        return directories
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}
