import Foundation

/// The config file, `config.json` (SPEC.md, Config file). Decoding is
/// strict: an unknown field is an error, so a typo never silently does
/// nothing. Rules that need the whole file live in ConfigValidator.
public struct Config: Sendable, Equatable {
    public static let supportedVersion = 1

    /// The `$schema` line for editors (S-039), kept as written.
    public var schema: String?
    public var version: Int
    public var runtime: Runtime
    public var ui: UI
    public var entries: [Entry]
    /// Action ids to actions. JSON objects have no order, so this is sorted
    /// by id wherever order matters.
    public var actions: [String: Action]
    public var contexts: [Context]

    public init(version: Int = Config.supportedVersion, runtime: Runtime = .init(), ui: UI = .init(),
                entries: [Entry], actions: [String: Action] = [:], contexts: [Context] = []) {
        self.version = version
        self.runtime = runtime
        self.ui = ui
        self.entries = entries
        self.actions = actions
        self.contexts = contexts
    }

    public struct Runtime: Sendable, Equatable {
        public var cancelKey = "Escape"
        /// "" turns Back off.
        public var backKey = "Backspace"
        public var showHud = true
        public var hudDelayMs = 0
        public var timeoutMs = 0
        public init() {}
    }

    public struct UI: Sendable, Equatable {
        public var theme = "system"
        public var position = "center"
        public var errorFlash = true
        public var errorBell = true
        public init() {}
    }

    /// A menu (no action) or a binding (with an action).
    public struct Entry: Sendable, Equatable {
        public var keys: String
        public var title: String
        public var action: String?
        /// An SF Symbol name, or a path starting with / or ~ for that file's
        /// icon (S-056). nil uses the action's icon, if it has one.
        public var icon: String?
        public init(keys: String, title: String, action: String? = nil, icon: String? = nil) {
            self.keys = keys
            self.title = title
            self.action = action
            self.icon = icon
        }
    }

    public struct Context: Sendable, Equatable {
        public var id: String
        public var apps: [String]
        public init(id: String, apps: [String]) {
            self.id = id
            self.apps = apps
        }
    }

    /// What Use Application does (S-046). Written as `mode` in the file;
    /// left out for the default, Focus or Start.
    public enum AppMode: String, Sendable, Equatable, CaseIterable {
        /// Bring the app forward if it's running, otherwise start it.
        case focusOrStart
        /// Bring the app forward only if it's running.
        case focus
        /// Start a new copy of the app, even if one is running.
        case start

        public static let `default` = AppMode.focusOrStart

        /// The glossary name shown in the UI.
        public var displayName: String {
            switch self {
            case .focusOrStart: "Focus or Start"
            case .focus: "Focus"
            case .start: "Start"
            }
        }
    }

    public indirect enum Action: Sendable, Equatable {
        case application(bundleId: String, mode: AppMode = .default)
        case open(target: String)
        case exec(command: [String], cwd: String?, env: [String: String])
        case send(keys: String)
        case contextual(variants: [String: Action], fallback: Action?)
        /// An action of any family in the registry (S-060).
        case family(AnyActionValue)

        public static var noop: Action { .family(AnyActionValue(BasicAction.noop)) }
        /// Show Help: open the Help page of the Bindings window (S-053).
        public static var help: Action { .family(AnyActionValue(BasicAction.help)) }

        /// The family's value, when this is a family's action.
        public var familyValue: (any ActionValue)? {
            if case let .family(value) = self { value.value } else { nil }
        }

        /// The `type` value in the file.
        public var type: String {
            switch self {
            case .application: "application"
            case .open: "open"
            case .exec: "exec"
            case .send: "send"
            case .contextual: "contextual"
            case let .family(value): value.value.type
            }
        }

        /// The glossary name shown in the UI.
        public var displayName: String {
            switch self {
            case .application: "Use Application"
            case .open: "Open"
            case .exec: "Run Command"
            case .send: "Send Shortcut"
            case .contextual: "Context Aware"
            case let .family(value): value.value.displayName
            }
        }
    }
}

// MARK: - Decoding

/// Any JSON key, so decoders can list the keys an object has.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Thrown for a field the format doesn't have. `path` names where it was.
public struct UnknownFieldError: Error, Sendable {
    public let field: String
    public let path: String
}

extension KeyedDecodingContainer where Key == AnyKey {
    func rejectUnknown(allowed: Set<String>, at path: String) throws {
        if let extra = allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
            throw UnknownFieldError(field: extra, path: path)
        }
    }

    func value<T: Decodable>(_ name: String, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: AnyKey(name)) ?? fallback
    }

    func required<T: Decodable>(_ name: String) throws -> T {
        try decode(T.self, forKey: AnyKey(name))
    }
}

extension Config: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // "$schema" lets editors find config.schema.json (S-039).
        try c.rejectUnknown(allowed: ["$schema", "version", "runtime", "ui", "entries", "actions", "contexts"], at: "the file")
        schema = try c.decodeIfPresent(String.self, forKey: AnyKey("$schema"))
        version = try c.required("version")
        runtime = try c.value("runtime", default: Runtime())
        ui = try c.value("ui", default: UI())
        entries = try c.required("entries")
        actions = try c.value("actions", default: [:])
        contexts = try c.value("contexts", default: [])
    }
}

extension Config.Runtime: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["cancelKey", "backKey", "showHud", "hudDelayMs", "timeoutMs"], at: "runtime")
        let d = Self()
        cancelKey = try c.value("cancelKey", default: d.cancelKey)
        backKey = try c.value("backKey", default: d.backKey)
        showHud = try c.value("showHud", default: d.showHud)
        hudDelayMs = try c.value("hudDelayMs", default: d.hudDelayMs)
        timeoutMs = try c.value("timeoutMs", default: d.timeoutMs)
    }
}

extension Config.UI: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["theme", "position", "errorFlash", "errorBell"], at: "ui")
        let d = Self()
        theme = try c.value("theme", default: d.theme)
        position = try c.value("position", default: d.position)
        errorFlash = try c.value("errorFlash", default: d.errorFlash)
        errorBell = try c.value("errorBell", default: d.errorBell)
    }
}

extension Config.Entry: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let keys: String = try c.value("keys", default: "")
        try c.rejectUnknown(allowed: ["keys", "title", "action", "icon"], at: keys.isEmpty ? "an entry" : "entry “\(keys)”")
        self.keys = try c.required("keys")
        title = try c.required("title")
        action = try c.decodeIfPresent(String.self, forKey: AnyKey("action"))
        icon = try c.decodeIfPresent(String.self, forKey: AnyKey("icon")).flatMap { $0.isEmpty ? nil : $0 }
    }
}

extension Config.Context: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["id", "apps"], at: "a context")
        id = try c.required("id")
        apps = try c.required("apps")
    }
}

extension Config.Action: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let type: String = try c.required("type")
        let path = "an action of type “\(type)”"
        let registry = ActionRegistry.from(decoder)
        if let family = registry.family(for: type) {
            self = .family(AnyActionValue(try family.init(type: type, fields: ActionFields(c, type: type))))
            return
        }
        switch type {
        case "application":
            try c.rejectUnknown(allowed: ["type", "bundleId", "mode"], at: path)
            let modeName: String = try c.value("mode", default: Config.AppMode.default.rawValue)
            guard let mode = Config.AppMode(rawValue: modeName) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath + [AnyKey("mode")],
                    debugDescription: "Unknown mode “\(modeName)” in an action of type “application”. Use focusOrStart, focus or start.",
                    underlyingError: RuleMarker(rule: .badAppMode)))
            }
            self = .application(bundleId: try c.required("bundleId"), mode: mode)
        case "open":
            try c.rejectUnknown(allowed: ["type", "target"], at: path)
            self = .open(target: try c.required("target"))
        case "exec":
            try c.rejectUnknown(allowed: ["type", "command", "cwd", "env"], at: path)
            self = .exec(command: try c.required("command"),
                         cwd: try c.decodeIfPresent(String.self, forKey: AnyKey("cwd")),
                         env: try c.value("env", default: [:]))
        case "send":
            try c.rejectUnknown(allowed: ["type", "keys"], at: path)
            self = .send(keys: try c.required("keys"))
        case "contextual":
            try c.rejectUnknown(allowed: ["type", "variants", "fallback"], at: path)
            self = .contextual(variants: try c.value("variants", default: [:]),
                               fallback: try c.decodeIfPresent(Config.Action.self, forKey: AnyKey("fallback")))
        default:
            let types = ["application", "open", "exec", "send"] + registry.kinds.map(\.type) + ["contextual"]
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath,
                debugDescription: "Unknown action type “\(type)”. Use \(types.dropLast().joined(separator: ", ")) or \(types.last!).",
                underlyingError: RuleMarker(rule: .unknownActionType)))
        }
    }
}
