import Foundation

/// Maximize (S-062): fill the usable area, and with `toggle`, go back.
public struct MaximizeAction: ActionValue {
    public var toggle: Bool

    public init(toggle: Bool = true) {
        self.toggle = toggle
    }

    public static let kinds = [ActionKind(type: "window.maximize", displayName: "Maximize", symbol: "arrow.up.left.and.arrow.down.right")]

    public var type: String { "window.maximize" }

    public static func blank(_ type: String) -> MaximizeAction {
        MaximizeAction()
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["toggle"])
        toggle = try fields.value("toggle", default: true)
    }

    /// `toggle` is left out for the default, true.
    public func write(to fields: inout ActionFieldWriter) {
        if !toggle { fields.bool("toggle", false) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema(["toggle": ["type": "boolean",
                                 "description": "true (default): a window that already fills the usable area goes back to where it was."]])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.maximize(toggle: toggle)))
    }
}
