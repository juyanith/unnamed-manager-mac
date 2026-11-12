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
