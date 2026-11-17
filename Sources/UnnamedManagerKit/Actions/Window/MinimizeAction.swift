import Foundation

/// Minimize (S-063): send the window to the Dock, as ⌘M does.
public struct MinimizeAction: ActionValue {
    public init() {}

    public static let kinds = [ActionKind(type: "window.minimize", displayName: "Minimize", symbol: "dock.arrow.down.rectangle")]

    public var type: String { "window.minimize" }

    public static func blank(_ type: String) -> MinimizeAction {
        MinimizeAction()
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow([])
    }

    public func write(to fields: inout ActionFieldWriter) {}

    /// Built-in action (spec v11): `window-minimize`.
    public static func builtIn(_ type: String, value: String?) -> MinimizeAction? {
        value == nil ? MinimizeAction() : nil
    }

    public static func builtInValues(_ type: String) -> [String?] { [nil] }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema()
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.minimize))
    }
}
