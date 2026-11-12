import Foundation

/// Which window Focus Window goes to (spec v2).
public enum FocusDirection: String, CaseIterable, Sendable {
    case left, right, up, down, next, previous

    /// The end of "No window to the left.", for a direction.
    var failure: String {
        switch self {
        case .left: "No window to the left."
        case .right: "No window to the right."
        case .up: "No window above."
        case .down: "No window below."
        case .next, .previous: "No other window to focus."
        }
    }
}

/// Focus Window (S-068, S-069): the nearest window in a direction, or the
/// next or previous one.
public struct FocusAction: ActionValue {
    public var direction: FocusDirection

    public init(_ direction: FocusDirection) {
        self.direction = direction
    }

    public static let kinds = [ActionKind(type: "window.focus", displayName: "Focus Window")]

    public var type: String { "window.focus" }

    public static func blank(_ type: String) -> FocusAction {
        FocusAction(.right)
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["direction"])
        guard let direction: FocusDirection = try fields.choice("direction") else {
            throw fields.invalid("direction", "Missing “direction” in \(fields.path).", rule: .missingField)
        }
        self.direction = direction
    }

    public func write(to fields: inout ActionFieldWriter) {
        fields.string("direction", direction.rawValue)
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema(["direction": ["enum": FocusDirection.allCases.map(\.rawValue)]], required: ["direction"])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.focus(direction)))
    }
}

extension WindowGeometry {
    /// The window Focus Window picks in a direction (S-068): of those whose
    /// center is within 45° of the direction from the current window's
    /// center, the nearest; a tie goes to the one that overlaps more on the
    /// other axis. nil when there's none that way.
    public static func neighbor(of current: CGRect, _ direction: FocusDirection, among windows: [CGRect]) -> Int? {
        let (dx, dy): (CGFloat, CGFloat) = switch direction {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, -1)
        case .down: (0, 1)
        case .next, .previous: (0, 0)
        }
        guard dx != 0 || dy != 0 else { return nil }
        struct Candidate { let index: Int; let distance: CGFloat; let overlap: CGFloat }
        let candidates = windows.indices.compactMap { index -> Candidate? in
            let window = windows[index]
            let x = window.midX - current.midX, y = window.midY - current.midY
            let along = x * dx + y * dy, across = abs(x * dy - y * dx)
            guard along > 0, across <= along else { return nil }
            let overlap = dx != 0
                ? max(0, min(window.maxY, current.maxY) - max(window.minY, current.minY))
                : max(0, min(window.maxX, current.maxX) - max(window.minX, current.minX))
            return Candidate(index: index, distance: (x * x + y * y).squareRoot(), overlap: overlap)
        }
        return candidates.min { a, b in
            abs(a.distance - b.distance) < 0.5 ? a.overlap > b.overlap : a.distance < b.distance
        }?.index
    }
}
