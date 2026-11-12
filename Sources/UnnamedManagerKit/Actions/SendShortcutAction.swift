import Foundation

/// Send Shortcut (S-012): presses chords in the app that was in front.
public struct SendShortcutAction: ActionValue {
    /// Chords separated by spaces, such as "Cmd+K S".
    public var keys: String

    public init(keys: String) {
        self.keys = keys
    }

    public static let kinds = [ActionKind(type: "send", displayName: "Send Shortcut")]

    public var type: String { "send" }

    public static func blank(_ type: String) -> SendShortcutAction {
        SendShortcutAction(keys: "")
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["keys"])
        keys = try fields.required("keys")
    }

    public func write(to fields: inout ActionFieldWriter) {
        fields.string("keys", keys)
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema(["keys": ["type": "string", "pattern": ConfigSchema.keysPattern]], required: ["keys"])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .send(try ActionPlanner.chords(keys))
    }
}
