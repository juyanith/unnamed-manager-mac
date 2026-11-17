import Foundation

/// Which window Focus Window goes to (spec v2; first and last from spec v6).
public enum FocusDirection: String, CaseIterable, Sendable {
    case left, right, up, down, next, previous, first, last

    /// The end of "No window to the left.", for a direction.
    public var failure: String {
        switch self {
        case .left: "No window to the left."
        case .right: "No window to the right."
        case .up: "No window above."
        case .down: "No window below."
        case .next, .previous: "No other window to focus."
        case .first, .last: "No window to focus."
        }
    }
}

/// Which windows Focus Window and Swap Window look at (spec v10).
public enum WindowScope: String, CaseIterable, Sendable {
    /// Windows on every display.
    case all
    /// Only the windows on the focused window's display.
    case display

    static var schema: [String: Any] {
        ["enum": allCases.map(\.rawValue), "description": "all (default): windows on every display. display: only the focused window's display."]
    }
}

/// Which window Focus Window goes to and Swap Window trades places with:
/// a direction, the next or previous one, the first or last one, or one
/// by number (spec v10 for Swap Window, v11 for Focus Window).
public enum WindowTarget: Sendable, Hashable {
    /// A word: a direction, next, previous, first or last.
    case window(FocusDirection)
    /// A place in Focus Window's order, from 1.
    case number(Int)

    static func schema(_ description: String) -> [String: Any] {
        ["oneOf": [["enum": FocusDirection.allCases.map(\.rawValue)], ["type": "integer", "minimum": 1]], "description": description]
    }

    /// What a number past the last window says.
    public static func pastTheEnd(_ number: Int, count: Int) -> String {
        "No window \(number). There \(count == 1 ? "is" : "are") \(count)."
    }

    /// The target in a built-in name, such as "left" or "3" (spec v11).
    init?(builtIn value: String) {
        if let number = BuiltInAction.number(value) {
            self = .number(number)
        } else if let direction = FocusDirection(rawValue: value) {
            self = .window(direction)
        } else {
            return nil
        }
    }

    /// The words, for the Action picker. Numbers are open-ended, so they aren't listed.
    static var builtInValues: [String?] { FocusDirection.allCases.map(\.rawValue) }
}

/// Focus Window (S-068, S-069, S-073): the nearest window in a direction,
/// the next or previous one, the first or last one, or one by number (S-079),
/// on every display or only the focused window's (S-078).
public struct FocusAction: ActionValue {
    /// The field the file names the target with: `target`, or `direction`,
    /// its old name before spec v11, which saving keeps.
    public static let currentField = "target"
    public static let oldField = "direction"

    public var target: WindowTarget
    public var scope: WindowScope
    public var field: String

    public init(_ target: WindowTarget, scope: WindowScope = .all, field: String = FocusAction.currentField) {
        self.target = target
        self.scope = scope
        self.field = field
    }

    public init(_ direction: FocusDirection, scope: WindowScope = .all) {
        self.init(.window(direction), scope: scope)
    }

    public static let kinds = [ActionKind(type: "window.focus", displayName: "Focus Window", symbol: "macwindow.on.rectangle")]

    public var type: String { "window.focus" }

    public static func blank(_ type: String) -> FocusAction {
        FocusAction(.right)
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow([Self.currentField, Self.oldField, "scope"])
        if fields.has(Self.currentField) && fields.has(Self.oldField) {
            throw fields.conflict(Self.oldField, with: Self.currentField)
        }
        field = fields.has(Self.oldField) ? Self.oldField : Self.currentField
        guard let target = try fields.target(field) else {
            throw fields.invalid(Self.currentField, "Missing “target” in \(fields.path).", rule: .missingField)
        }
        self.target = target
        scope = try fields.choice("scope") ?? .all
    }

    /// The scope is left out when it's the default, every display.
    public func write(to fields: inout ActionFieldWriter) {
        fields.target(field, target)
        if scope != .all { fields.string("scope", scope.rawValue) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            currentField: WindowTarget.schema("The window to focus: a direction, next, previous, first, last, or its number in the order, from 1."),
            oldField: WindowTarget.schema("The old name of target, from before spec v11. The same values."),
            "scope": WindowScope.schema,
        ])
    }

    /// Built-in actions (spec v11): `window-focus-left`, `window-focus-2` and the others.
    public static func builtIn(_ type: String, value: String?) -> FocusAction? {
        value.flatMap(WindowTarget.init(builtIn:)).map { FocusAction($0) }
    }

    public static func builtInValues(_ type: String) -> [String?] {
        WindowTarget.builtInValues
    }

    /// Each direction shows its arrow, and a number shows one.
    public func iconSource(home: URL) -> IconSource? {
        let symbol = switch target {
        case .window(.left): "arrow.left.square"
        case .window(.right): "arrow.right.square"
        case .window(.up): "arrow.up.square"
        case .window(.down): "arrow.down.square"
        case .window(.next): "arrow.forward.circle"
        case .window(.previous): "arrow.backward.circle"
        case .window(.first): "arrow.left.to.line.circle"
        case .window(.last): "arrow.right.to.line.circle"
        case .number: "number.circle"
        }
        return .symbol(symbol)
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.focus(target, scope: scope)))
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
        case .next, .previous, .first, .last: (0, 0)
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

    /// The order Next and Previous go through, and First and Last are the
    /// ends of (S-069, S-073): by display, left to right, then by window
    /// center, left to right and then top to bottom (spec v6).
    /// `owners` (process ids) break the ties that are left, so the same
    /// windows always give the same order, whatever their order here.
    public static func cycleOrder(_ windows: [CGRect], owners: [Int32], screens: [Screen]) -> [Int] {
        let displays = screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        func display(_ window: CGRect) -> Int {
            screen(for: window, among: screens).flatMap { found in displays.firstIndex { $0 == found } } ?? 0
        }
        let keys = windows.indices.map { index in
            let window = windows[index]
            return (display(window), window.midX, window.midY, owners[index], window.width, window.height)
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
