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
    /// Settings the window actions share (spec v3).
    public var windows = Windows()
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

    public struct Windows: Sendable, Equatable {
        /// Points Place Window, Fill and Arrange Windows leave around windows and between them.
        public var gap: Double
        /// The smallest cell Arrange Windows makes, in steps (spec v24). It
        /// sets the most columns and rows it picks.
        public var minCell: WindowSteps
        public static let standardMinCell = WindowSteps(across: 6, down: 6)
        /// Settings for each display, keyed by its size in points, such as "3840x1080" (spec v24).
        public var displays: [String: Display]
        /// Spec v8 to v23: the most columns and rows Arrange Windows picked.
        /// From spec v24 they load with a warning and do nothing; nil when
        /// the file leaves them out. The writer drops them.
        public var maxColumns: Int?
        public var maxRows: Int?
        /// The range the retired limits took.
        public static let limitRange = 1...8
        /// What Focus Window and Swap Window see (spec v12): the square a
        /// window must show to count, and the span it must share to be in line;
        /// how close tops are in one row of the order; how close gaps tie.
        public var minVisible: Double
        public var rowTolerance: Double
        public var tieTolerance: Double
        /// Quit an app when its last window closes (spec v16, Mac only).
        public var quitOnClose: Bool
        /// How long after a window closes its app's windows are counted (spec v16).
        public var quitOnCloseDelayMs: Int
        /// Rules for each app's windows, by bundle id (spec v15).
        public var apps: [String: AppRules]

        public init(gap: Double = 8, minCell: WindowSteps = Self.standardMinCell, displays: [String: Display] = [:],
                    maxColumns: Int? = nil, maxRows: Int? = nil,
                    minVisible: Double = 20, rowTolerance: Double = 20, tieTolerance: Double = 2, quitOnClose: Bool = false, quitOnCloseDelayMs: Int = 500, apps: [String: AppRules] = [:]) {
            self.gap = gap
            self.minCell = minCell
            self.displays = displays
            self.maxColumns = maxColumns
            self.maxRows = maxRows
            self.minVisible = minVisible
            self.rowTolerance = rowTolerance
            self.tieTolerance = tieTolerance
            self.quitOnClose = quitOnClose
            self.quitOnCloseDelayMs = quitOnCloseDelayMs
            self.apps = apps
        }

        /// The rules for one app's windows (spec v15): which window actions
        /// take part with them, and whether Quit on Close quits it (spec v16).
        /// A missing rule is true.
        public struct AppRules: Sendable, Equatable {
            public var focus: Bool
            public var swap: Bool
            public var arrange: Bool
            public var quit: Bool
            /// The smallest width and height, in points, Arrange Windows and
            /// Tidy Windows give the app's windows (spec v24). 0 sets none.
            public var minWidth: Double
            public var minHeight: Double

            public init(focus: Bool = true, swap: Bool = true, arrange: Bool = true, quit: Bool = true,
                        minWidth: Double = 0, minHeight: Double = 0) {
                self.focus = focus
                self.swap = swap
                self.arrange = arrange
                self.quit = quit
                self.minWidth = minWidth
                self.minHeight = minHeight
            }

            /// Left out of everything, as a new app in Settings starts.
            public static let leftOutOfAll = Self(focus: false, swap: false, arrange: false, quit: false)
        }

        /// One display's own settings (spec v24): steps in place of the
        /// guess, and a smallest cell in place of `minCell`.
        public struct Display: Sendable, Equatable {
            public var steps: WindowSteps?
            public var minCell: WindowSteps?

            public init(steps: WindowSteps? = nil, minCell: WindowSteps? = nil) {
                self.steps = steps
                self.minCell = minCell
            }
        }

        /// A display's key in `displays`: its width, an x and its height, in points.
        public static func displayKey(for size: CGSize) -> String {
            "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }

        /// Whether a key in `displays` is a width, an x and a height (spec v24).
        public static func isDisplayKey(_ key: String) -> Bool {
            key.wholeMatch(of: /[1-9][0-9]*x[1-9][0-9]*/) != nil
        }

        /// The steps of a display, by its whole frame's size: its own, or the guess.
        public func steps(for display: CGSize) -> WindowSteps {
            (displays[Self.displayKey(for: display)]?.steps ?? WindowSteps.guess(for: display)).clamped
        }

        /// The smallest cell on a display, no larger than its steps.
        public func minCell(for display: CGSize) -> WindowSteps {
            let steps = steps(for: display), cell = (displays[Self.displayKey(for: display)]?.minCell ?? minCell).clamped
            return WindowSteps(across: min(cell.across, steps.across), down: min(cell.down, steps.down))
        }

        /// The most columns and rows Arrange Windows picks on a display (spec v24).
        public func limits(for display: CGSize) -> (columns: Int, rows: Int) {
            let steps = steps(for: display), cell = minCell(for: display)
            return (max(1, steps.across / cell.across), max(1, steps.down / cell.down))
        }

        /// An app's smallest size, in points; zero where it sets none.
        public func minimum(for app: String?) -> CGSize {
            guard let rules = app.flatMap({ apps[$0] }) else { return .zero }
            return CGSize(width: max(0, rules.minWidth), height: max(0, rules.minHeight))
        }

        /// The apps whose rule leaves them out of an action, such as `\.arrange`.
        public func leftOut(of rule: KeyPath<AppRules, Bool>) -> Set<String> {
            Set(apps.filter { !$0.value[keyPath: rule] }.keys)
        }
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
        /// On a leader: its menus are held menus (spec v18).
        public var hold: Bool
        /// Makes the menu a list the app fills when it opens (spec v18).
        public var list: List?
        public init(keys: String, title: String, action: String? = nil, icon: String? = nil, hold: Bool = false,
                    list: List? = nil) {
            self.keys = keys
            self.title = title
            self.action = action
            self.icon = icon
            self.hold = hold
            self.list = list
        }
    }

    /// What a list holds (spec v18, Lists). Values stay as written, so the
    /// validator can name a wrong one. `minimized`, `hidden` and `spaces`
    /// are nil when the file leaves them out, since with `"choose": "swap"`
    /// writing one at all is an error (spec v19).
    public struct List: Sendable, Equatable {
        public static let recentWindows = "windows.recent"
        public static let countRange = 1...99
        /// What choosing an item does (spec v19).
        public static let chooseValues = ["focus", "swap"]

        public var type: String
        public var count: Int
        public var minimized: Bool?
        public var hidden: Bool?
        /// `all` or `current`.
        public var spaces: String?
        /// `all` or `display`.
        public var scope: String
        /// `focus` or `swap`.
        public var choose: String

        public init(type: String = Self.recentWindows, count: Int = 9, minimized: Bool? = nil, hidden: Bool? = nil,
                    spaces: String? = nil, scope: String = "all", choose: String = "focus") {
            self.type = type
            self.count = count
            self.minimized = minimized
            self.hidden = hidden
            self.spaces = spaces
            self.scope = scope
            self.choose = choose
        }

        /// Choosing an item swaps with its window, instead of focusing it.
        public var swaps: Bool { choose == "swap" }
        /// Swap only works with windows that are shown on the current Space.
        public var includesMinimized: Bool { !swaps && (minimized ?? true) }
        public var includesHidden: Bool { !swaps && (hidden ?? true) }
        /// Only the current Space of each display.
        public var currentSpaceOnly: Bool { swaps || spaces == "current" }
        /// Only the focused window's display.
        public var displayOnly: Bool { scope == "display" }

        /// The same list with the fields that are at their default left
        /// out, as the file has them.
        public var normalized: List {
            var list = self
            if list.minimized == true { list.minimized = nil }
            if list.hidden == true { list.hidden = nil }
            if list.spaces == "all" { list.spaces = nil }
            return list
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
        case contextual(variants: [String: Action], fallback: Action?)
        /// An action of any family in the registry (S-060).
        case family(AnyActionValue)

        public static func application(bundleId: String, mode: AppMode = .default) -> Action {
            .family(AnyActionValue(UseApplicationAction(bundleId: bundleId, mode: mode)))
        }
        public static func open(target: String) -> Action { .family(AnyActionValue(OpenAction(target: target))) }
        public static func exec(command: [String], cwd: String?, env: [String: String]) -> Action {
            .family(AnyActionValue(RunCommandAction(command: command, cwd: cwd, env: env)))
        }
        public static func send(keys: String) -> Action { .family(AnyActionValue(SendShortcutAction(keys: keys))) }
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
            case .contextual: "contextual"
            case let .family(value): value.value.type
            }
        }

        /// The glossary name shown in the UI.
        public var displayName: String {
            switch self {
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
        try c.rejectUnknown(allowed: ["$schema", "version", "runtime", "ui", "windows", "entries", "actions", "contexts"], at: "the file")
        schema = try c.decodeIfPresent(String.self, forKey: AnyKey("$schema"))
        version = try c.required("version")
        runtime = try c.value("runtime", default: Runtime())
        ui = try c.value("ui", default: UI())
        windows = try c.value("windows", default: Windows())
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

extension Config.Windows: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["gap", "minCell", "displays", "maxColumns", "maxRows", "minVisible", "rowTolerance", "tieTolerance",
                                      "quitOnClose", "quitOnCloseDelayMs", "apps"], at: "windows")
        let d = Self()
        gap = try c.value("gap", default: d.gap)
        minCell = try c.value("minCell", default: d.minCell)
        displays = try c.value("displays", default: d.displays)
        maxColumns = try c.decodeIfPresent(Int.self, forKey: AnyKey("maxColumns"))
        maxRows = try c.decodeIfPresent(Int.self, forKey: AnyKey("maxRows"))
        minVisible = try c.value("minVisible", default: d.minVisible)
        rowTolerance = try c.value("rowTolerance", default: d.rowTolerance)
        tieTolerance = try c.value("tieTolerance", default: d.tieTolerance)
        quitOnClose = try c.value("quitOnClose", default: d.quitOnClose)
        quitOnCloseDelayMs = try c.value("quitOnCloseDelayMs", default: d.quitOnCloseDelayMs)
        apps = try c.value("apps", default: d.apps)
    }
}

extension Config.Windows.AppRules: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["focus", "swap", "arrange", "quit", "minWidth", "minHeight"], at: "windows.apps")
        let d = Self()
        focus = try c.value("focus", default: d.focus)
        swap = try c.value("swap", default: d.swap)
        arrange = try c.value("arrange", default: d.arrange)
        quit = try c.value("quit", default: d.quit)
        minWidth = try c.value("minWidth", default: d.minWidth)
        minHeight = try c.value("minHeight", default: d.minHeight)
    }
}

extension Config.Windows.Display: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["steps", "minCell"], at: "windows.displays")
        steps = try c.decodeIfPresent(WindowSteps.self, forKey: AnyKey("steps"))
        minCell = try c.decodeIfPresent(WindowSteps.self, forKey: AnyKey("minCell"))
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
        try c.rejectUnknown(allowed: ["keys", "title", "action", "icon", "hold", "list"], at: keys.isEmpty ? "an entry" : "entry “\(keys)”")
        self.keys = try c.required("keys")
        title = try c.required("title")
        action = try c.decodeIfPresent(String.self, forKey: AnyKey("action"))
        icon = try c.decodeIfPresent(String.self, forKey: AnyKey("icon")).flatMap { $0.isEmpty ? nil : $0 }
        hold = try c.value("hold", default: false)
        list = try c.decodeIfPresent(Config.List.self, forKey: AnyKey("list"))
    }
}

extension Config.List: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["type", "count", "minimized", "hidden", "spaces", "scope", "choose"], at: "a list")
        let d = Self()
        type = try c.required("type")
        count = try c.value("count", default: d.count)
        minimized = try c.decodeIfPresent(Bool.self, forKey: AnyKey("minimized"))
        hidden = try c.decodeIfPresent(Bool.self, forKey: AnyKey("hidden"))
        spaces = try c.decodeIfPresent(String.self, forKey: AnyKey("spaces"))
        scope = try c.value("scope", default: d.scope)
        choose = try c.value("choose", default: d.choose)
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
        case "contextual":
            try c.rejectUnknown(allowed: ["type", "variants", "fallback"], at: path)
            self = .contextual(variants: try c.value("variants", default: [:]),
                               fallback: try c.decodeIfPresent(Config.Action.self, forKey: AnyKey("fallback")))
        default:
            let types = registry.kinds.filter { $0.replacedBy == nil }.map(\.type) + ["contextual"]
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath,
                debugDescription: "Unknown action type “\(type)”. Use \(types.dropLast().joined(separator: ", ")) or \(types.last!).",
                underlyingError: RuleMarker(rule: .unknownActionType)))
        }
    }
}
