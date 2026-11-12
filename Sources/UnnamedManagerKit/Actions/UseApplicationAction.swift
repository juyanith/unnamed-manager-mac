import Foundation

/// Use Application (S-006, S-046): focus an app, start it, or both, by its mode.
public struct UseApplicationAction: ActionValue {
    public var bundleId: String
    public var mode: Config.AppMode

    public init(bundleId: String, mode: Config.AppMode = .default) {
        self.bundleId = bundleId
        self.mode = mode
    }

    public static let kinds = [ActionKind(type: "application", displayName: "Use Application")]

    public var type: String { "application" }

    public static func blank(_ type: String) -> UseApplicationAction {
        UseApplicationAction(bundleId: "")
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["bundleId", "mode"])
        let modeName: String = try fields.value("mode", default: Config.AppMode.default.rawValue)
        guard let mode = Config.AppMode(rawValue: modeName) else {
            throw fields.invalid("mode", "Unknown mode “\(modeName)” in an action of type “application”. Use focusOrStart, focus or start.",
                                 rule: .badAppMode)
        }
        self.mode = mode
        bundleId = try fields.required("bundleId")
    }

    /// `mode` is left out for the default, Focus or Start.
    public func write(to fields: inout ActionFieldWriter) {
        fields.string("bundleId", bundleId)
        if mode != .default { fields.string("mode", mode.rawValue) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        let mode: [String: Any] = [
            "enum": Config.AppMode.allCases.map(\.rawValue),
            "description": "focusOrStart (default): bring it forward, starting it if needed. focus: only if running. start: a new copy.",
        ]
        // The Windows app names an app by exe or appId (spec v4). The Mac
        // reads only bundleId, but the schema is shared, so it lists all three.
        return ActionSchema(["bundleId": ["type": "string"], "mode": mode], required: ["bundleId"], alternatives: [
            ActionSchema([
                "exe": ["type": "string", "pattern": "\\.[Ee][Xx][Ee]$",
                        "description": "Windows: the program's file name, such as Code.exe, or its full path."],
                "mode": mode,
            ], required: ["exe"]),
            ActionSchema([
                "appId": ["type": "string", "minLength": 1,
                          "description": "Windows: an AppUserModelID, for Store and packaged apps."],
                "mode": mode,
            ], required: ["appId"]),
        ])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        switch mode {
        case .focusOrStart: .openApp(bundleId: bundleId)
        case .focus: .focusApp(bundleId: bundleId)
        case .start: .startApp(bundleId: bundleId)
        }
    }

    /// The app's own icon (S-054).
    public func iconSource(home: URL) -> IconSource? {
        .app(bundleId)
    }
}
