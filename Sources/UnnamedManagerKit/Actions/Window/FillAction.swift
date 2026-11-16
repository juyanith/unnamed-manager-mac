import Foundation

/// Fill (S-062, S-074): fill the usable area, less the gap, and with
/// `toggle`, go back. Before spec v7 this was Maximize, `window.maximize`,
/// which still loads and is written back under the name the file used.
public struct FillAction: ActionValue {
    public static let currentType = "window.fill"
    public static let oldType = "window.maximize"

    public var toggle: Bool
    /// `window.fill`, or the old name when the file uses it.
    public var type: String

    public init(toggle: Bool = true, type: String = FillAction.currentType) {
        self.toggle = toggle
        self.type = type
    }

    public static let kinds = [
        ActionKind(type: currentType, displayName: "Fill", symbol: "arrow.up.left.and.arrow.down.right"),
        ActionKind(type: oldType, displayName: "Fill", symbol: "arrow.up.left.and.arrow.down.right", replacedBy: currentType),
    ]

    public static func blank(_ type: String) -> FillAction {
        FillAction(type: type)
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["toggle"])
        toggle = try fields.value("toggle", default: true)
        self.type = type
    }

    /// `toggle` is left out for the default, true.
    public func write(to fields: inout ActionFieldWriter) {
        if !toggle { fields.bool("toggle", false) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        let toggle = "true (default): a window that already fills the usable area goes back to where it was."
        return ActionSchema(["toggle": ["type": "boolean",
                                        "description": type == oldType ? "The old name of \(currentType). \(toggle)" : toggle]])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.fill(toggle: toggle)))
    }
}
