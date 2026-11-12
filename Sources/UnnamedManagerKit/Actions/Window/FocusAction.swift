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

    public static let kinds = [ActionKind(type: "window.focus", displayName: "Focus Window", symbol: "macwindow.on.rectangle")]

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

    /// Each direction shows its arrow.
    public func iconSource(home: URL) -> IconSource? {
        let symbol = switch direction {
        case .left: "arrow.left.square"
        case .right: "arrow.right.square"
        case .up: "arrow.up.square"
        case .down: "arrow.down.square"
        case .next: "arrow.forward.circle"
        case .previous: "arrow.backward.circle"
        }
        return .symbol(symbol)
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

    /// The order Next and Previous go through (S-069): by display, left to
    /// right, then by window center, top to bottom and then left to right.
    /// `owners` (process ids) break the ties that are left, so the same
    /// windows always give the same order, whatever their order here.
    public static func cycleOrder(_ windows: [CGRect], owners: [Int32], screens: [Screen]) -> [Int] {
        let displays = screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        func display(_ window: CGRect) -> Int {
            screen(for: window, among: screens).flatMap { found in displays.firstIndex { $0 == found } } ?? 0
        }
        let keys = windows.indices.map { index in
            let window = windows[index]
            return (display(window), window.midY, window.midX, owners[index], window.width, window.height)
        }
        return windows.indices.sorted { a, b in
            let x = keys[a], y = keys[b]
            if (x.0, x.1, x.2, x.3) != (y.0, y.1, y.2, y.3) { return (x.0, x.1, x.2, x.3) < (y.0, y.1, y.2, y.3) }
            return (x.4, x.5, a) < (y.4, y.5, b)
        }
    }

    /// The window after `current` in `order`, wrapping at the ends; the
    /// first (or last) when the current one isn't in it. nil when there's
    /// no other window.
    public static func step(from current: Int?, in order: [Int], _ direction: FocusDirection) -> Int? {
        let others = order.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        guard let current, let position = order.firstIndex(of: current) else {
            return direction == .previous ? others.last : others.first
        }
        let offset = direction == .previous ? order.count - 1 : 1
        return order[(position + offset) % order.count]
    }
}
