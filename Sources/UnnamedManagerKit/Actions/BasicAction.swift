import Foundation

/// Do Nothing and Show Help (S-053): the kinds with no fields.
public enum BasicAction: String, ActionValue {
    case noop
    /// Open the Help page of the Bindings window.
    case help

    public static let kinds = [
        ActionKind(type: "noop", displayName: "Do Nothing"),
        ActionKind(type: "help", displayName: "Show Help"),
    ]

    public var type: String { rawValue }

    public static func blank(_ type: String) -> BasicAction {
        BasicAction(rawValue: type) ?? .noop
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow([])
        self = BasicAction(rawValue: type) ?? .noop
    }

    public func write(to fields: inout ActionFieldWriter) {}

    /// Built-in actions (spec v11): `help` and `noop`.
    public static func builtIn(_ type: String, value: String?) -> BasicAction? {
        value == nil ? BasicAction(rawValue: type) : nil
    }

    public static func builtInValues(_ type: String) -> [String?] { [nil] }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema()
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        switch self {
        case .noop: .nothing
        case .help: .showHelp
        }
    }
}
