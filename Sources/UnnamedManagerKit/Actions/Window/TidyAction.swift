import Foundation

/// Tidy Windows (spec v24): snaps the windows on the focused window's
/// display into the columns and rows their places suggest.
public struct TidyAction: ActionValue {
    public init() {}

    public static let kinds = [ActionKind(type: "window.tidy", displayName: "Tidy Windows", symbol: "rectangle.3.group")]

    public var type: String { "window.tidy" }

    public static func blank(_ type: String) -> TidyAction {
        TidyAction()
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow([])
    }

    public func write(to fields: inout ActionFieldWriter) {}

    /// Built-in action (spec v24): `window-tidy`.
    public static func builtIn(_ type: String, value: String?) -> TidyAction? {
        value == nil ? TidyAction() : nil
    }

    public static func builtInValues(_ type: String) -> [String?] { [nil] }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema()
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.tidy))
    }
}

/// Undo Layout (spec v24): puts back the windows the last Tidy Windows or
/// Arrange Windows moved on the focused window's display, and puts the
/// layout back when pressed again.
public struct UndoLayoutAction: ActionValue {
    public init() {}

    public static let kinds = [ActionKind(type: "window.undo", displayName: "Undo Layout", symbol: "arrow.uturn.backward")]

    public var type: String { "window.undo" }

    public static func blank(_ type: String) -> UndoLayoutAction {
        UndoLayoutAction()
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow([])
    }

    public func write(to fields: inout ActionFieldWriter) {}

    /// Built-in action (spec v24): `window-undo`.
    public static func builtIn(_ type: String, value: String?) -> UndoLayoutAction? {
        value == nil ? UndoLayoutAction() : nil
    }

    public static func builtInValues(_ type: String) -> [String?] { [nil] }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema()
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.undoLayout))
    }
}
