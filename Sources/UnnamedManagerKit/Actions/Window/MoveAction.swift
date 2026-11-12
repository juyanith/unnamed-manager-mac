import Foundation

/// Move Window (S-066): to a spot, or by points. The size stays the same.
public enum MoveAction: ActionValue {
    /// Fractions of the free space: 0 is the left or top edge, 0.5
    /// centered, 1 the right or bottom edge.
    case to(x: Double, y: Double)
    /// Points. Positive `dy` moves down.
    case by(dx: Double, dy: Double)

    public static let kinds = [ActionKind(type: "window.move", displayName: "Move Window")]

    public var type: String { "window.move" }

    public static func blank(_ type: String) -> MoveAction {
        .to(x: 0.5, y: 0.5)
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["to", "by"])
        if try fields.one(of: ["to", "by"]) == "to" {
            let to = try fields.numbers("to", required: ["x", "y"])!
            for name in ["x", "y"] where !(0...1).contains(to[name]!) {
                throw fields.badFraction("to", "“\(name)” must be from 0 to 1")
            }
            self = .to(x: to["x"]!, y: to["y"]!)
        } else {
            let by = try fields.numbers("by", required: [], others: ["dx", "dy"])!
            self = .by(dx: by["dx"] ?? 0, dy: by["dy"] ?? 0)
        }
    }

    public func write(to fields: inout ActionFieldWriter) {
        switch self {
        case let .to(x, y):
            fields.numbers("to", [("x", x), ("y", y)])
        case let .by(dx, dy):
            fields.numbers("by", [("dx", dx), ("dy", dy)].filter { $0.1 != 0 })
        }
    }

    public static func schema(_ type: String) -> ActionSchema {
        var to = WindowSchema.object(["x": WindowSchema.fraction, "y": WindowSchema.fraction], required: ["x", "y"])
        to["description"] = "Fractions of the free space: 0 is the left or top edge, 0.5 centered, 1 the right or bottom edge."
        var by = WindowSchema.object(["dx": WindowSchema.points, "dy": WindowSchema.points], required: [])
        by["description"] = "Points. Positive dy moves down."
        return ActionSchema(["to": to, "by": by])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.move(self)))
    }
}
