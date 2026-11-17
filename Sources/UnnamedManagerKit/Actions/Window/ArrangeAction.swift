import Foundation

/// Whether Arrange Windows' groups are columns or rows (spec v8).
public enum ArrangeLayout: String, CaseIterable, Sendable {
    /// Columns on a wide screen, rows on a tall one.
    case auto
    case columns, rows
}

/// How many windows Arrange Windows lays out (spec v8).
public enum ArrangeCount: Sendable, Hashable {
    /// The focused window and the ones used before it.
    case windows(Int)
    /// Every window on the display, up to the settings' limit.
    case all
}

/// Arrange Windows (S-075, S-076): the windows used last, on the focused
/// window's display, in a grid of columns or rows.
public struct ArrangeAction: ActionValue {
    /// The numbers `count` and `groups` take, and the most windows ever arranged.
    public static let countRange = 2...8
    public static let groupsRange = 1...8

    public var count: ArrangeCount
    /// nil lets the app pick, up to the settings' limit.
    public var groups: Int?
    public var layout: ArrangeLayout

    public init(count: ArrangeCount = .windows(2), groups: Int? = nil, layout: ArrangeLayout = .auto) {
        self.count = count
        self.groups = groups
        self.layout = layout
    }

    public static let kinds = [ActionKind(type: "window.arrange", displayName: "Arrange Windows", symbol: "rectangle.split.2x1")]

    public var type: String { "window.arrange" }

    public static func blank(_ type: String) -> ArrangeAction {
        ArrangeAction()
    }

    /// `count` as the file has it: a number, or a word that must be "all".
    private enum RawCount: Decodable {
        case number(Int), word(String)

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Int.self) {
                self = .number(number)
            } else if let word = try? value.decode(String.self) {
                self = .word(word)
            } else {
                throw DecodingError.typeMismatch(Int.self, .init(codingPath: decoder.codingPath,
                                                                 debugDescription: "Expected a whole number or \"all\"."))
            }
        }
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["count", "groups", "layout"])
        let range = Self.countRange
        switch try fields.optional("count") as RawCount? {
        case nil:
            count = .windows(2)
        case .word("all"):
            count = .all
        case let .number(number) where range.contains(number):
            count = .windows(number)
        default:
            throw fields.invalid("count", "“count” in \(fields.path) must be from \(range.lowerBound) to \(range.upperBound), or \"all\".",
                                 rule: .badWindowValue)
        }
        groups = try fields.optional("groups")
        if let groups {
            guard Self.groupsRange.contains(groups) else {
                throw fields.invalid("groups", "“groups” in \(fields.path) must be from 1 to \(Self.groupsRange.upperBound).",
                                     rule: .badWindowValue)
            }
            if case let .windows(number) = count, groups > number {
                throw fields.invalid("groups", "“groups” in \(fields.path) can't be more than “count”, \(number).", rule: .badWindowValue)
            }
        }
        layout = try fields.choice("layout") ?? .auto
    }

    /// Defaults are left out: a count of 2, no groups, the auto layout.
    public func write(to fields: inout ActionFieldWriter) {
        switch count {
        case .windows(2): break
        case let .windows(number): fields.number("count", Double(number))
        case .all: fields.string("count", "all")
        }
        if let groups { fields.number("groups", Double(groups)) }
        if layout != .auto { fields.string("layout", layout.rawValue) }
    }

    /// Built-in actions (spec v11): `window-arrange`, `window-arrange-3` up to 8, and `window-arrange-all`.
    public static func builtIn(_ type: String, value: String?) -> ArrangeAction? {
        switch value {
        case nil: ArrangeAction()
        case "all": ArrangeAction(count: .all)
        case let value?: BuiltInAction.number(value).flatMap { countRange.contains($0) ? ArrangeAction(count: .windows($0)) : nil }
        }
    }

    public static func builtInValues(_ type: String) -> [String?] {
        [nil] + countRange.map { String($0) } + ["all"]
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "count": ["oneOf": [["type": "integer", "minimum": countRange.lowerBound, "maximum": countRange.upperBound], ["enum": ["all"]]],
                      "description": "How many windows: the focused one and the ones used before it. \"all\" is every window on the display, up to windows.maxColumns times windows.maxRows. Default 2."],
            "groups": ["type": "integer", "minimum": groupsRange.lowerBound, "maximum": groupsRange.upperBound,
                       "description": "How many columns or rows. Without it, as many as there are windows, up to windows.maxColumns or windows.maxRows."],
            "layout": ["enum": ArrangeLayout.allCases.map(\.rawValue),
                       "description": "auto (default) is columns on a wide screen and rows on a tall one."],
        ])
    }

    /// Rows, every window, and three or more each show their own grid.
    public func iconSource(home: URL) -> IconSource? {
        if layout == .rows { return .symbol("rectangle.split.1x2") }
        return switch count {
        case .all: .symbol("rectangle.split.2x2")
        case .windows(2): .symbol("rectangle.split.2x1")
        case .windows: .symbol("rectangle.split.3x1")
        }
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.arrange(self)))
    }
}

/// The grid Arrange Windows makes, and which window goes in which cell
/// (spec v8, with the focused window's cell from spec v9). Pure, so both the app and the tests can ask it.
public enum ArrangeGrid {
    /// One cell, as fractions of the usable area. Neighbours get the same
    /// value for the edge they share, so they round to the same point.
    public struct Cell: Sendable, Equatable {
        public var minX: Double, maxX: Double, minY: Double, maxY: Double

        /// The cell in the usable area, before the gap. Edges round to whole points.
        public func rect(in usable: CGRect) -> CGRect {
            let left = (minX * usable.width).rounded(), right = (maxX * usable.width).rounded()
            let top = (minY * usable.height).rounded(), bottom = (maxY * usable.height).rounded()
            return CGRect(x: usable.minX + left, y: usable.minY + top, width: right - left, height: bottom - top)
        }
    }

    /// How many windows each group holds, for `count` windows in `groups`
    /// columns or rows. The plain grid has `per` cells in every group, and
    /// `spare` of them have no window. The focused window, in the group
    /// `focused`, gets the spare cells: its cell spans `span` cells there.
    /// With more spare cells than its group has, the other groups share
    /// the rest, the ones with a single window on the right or at the top.
    static func shape(count: Int, groups: Int, rows: Bool, focused: Int) -> (sizes: [Int], per: Int, focused: Int?, span: Int) {
        let per = (count + groups - 1) / groups, spare = groups * per - count
        guard spare > 0 else { return (Array(repeating: per, count: groups), per, nil, 1) }
        let span = min(spare + 1, per), own = per - span + 1
        let others = groups - 1, base = (count - own) / others, extra = (count - own) % others
        var sizes = (0..<others).map { base + ((rows ? $0 >= others - extra : $0 < extra) ? 1 : 0) }
        sizes.insert(own, at: focused)
        return (sizes, per, focused, span)
    }

    /// Where each window goes. `windows` are the frames of the candidates
    /// on the display, the focused one first, then front to back. The
    /// result has an index into `windows` and its cell, for the windows
    /// that are arranged; the others stay as they are.
    public static func plan(_ action: ArrangeAction, maxColumns: Int, maxRows: Int, usable: CGRect,
                            windows: [CGRect]) -> [(window: Int, cell: Cell)] {
        guard !windows.isEmpty else { return [] }
        let limit = ArrangeAction.countRange.upperBound
        let count = switch action.count {
        case let .windows(number): number
        case .all: max(1, min(windows.count, limit, maxColumns * maxRows))
        }
        let rows = action.layout == .rows || (action.layout == .auto && usable.height > usable.width)
        let groups = min(count, max(1, action.groups ?? (rows ? maxRows : maxColumns)))
        let used = Array(windows.indices.prefix(count))

        /// Windows keep the order they're in: by center along the groups,
        /// or across one. Centers within the tolerance are the same; what's
        /// still tied goes by use, the window used more recently further
        /// right, or further up.
        func before(_ a: Int, _ b: Int, along: Bool) -> Bool {
            let byX = along != rows
            let first: (CGRect) -> CGFloat = byX ? \.midX : \.midY
            let second: (CGRect) -> CGFloat = byX ? \.midY : \.midX
            for key in [first, second] where abs(key(windows[a]) - key(windows[b])) > WindowGeometry.tolerance {
                return key(windows[a]) < key(windows[b])
            }
            return byX ? a > b : a < b
        }
        /// A missing window (nil) counts as furthest left and furthest down, so the empty cells end there.
        func ordered(_ members: [Int?], along: Bool) -> [Int?] {
            let real: [Int?] = members.compactMap { $0 }.sorted { before($0, $1, along: along) }
            let missing = [Int?](repeating: nil, count: members.count - real.count)
            return along != rows ? missing + real : real + missing
        }

        // The focused window stays in the group its center is in.
        let center = rows ? (windows[0].midY - usable.minY) / usable.height : (windows[0].midX - usable.minX) / usable.width
        let home = center.isFinite ? min(groups - 1, max(0, Int((center * CGFloat(groups)).rounded(.down)))) : 0
        let shape = shape(count: count, groups: groups, rows: rows, focused: home)
        var order = ordered(used + Array(repeating: nil, count: count - used.count), along: true)
        // The focused window is dealt into its own group; the others fill the groups in order.
        if shape.focused != nil { order.removeAll { $0 == 0 } }
        var rest = order[...], result: [(window: Int, cell: Cell)] = []
        for (group, size) in shape.sizes.enumerated() {
            let own = group == shape.focused
            let taken = rest.prefix(own ? size - 1 : size)
            rest = rest.dropFirst(taken.count)
            // The focused window's group keeps the plain grid's cells; another group splits equally.
            let parts = own ? shape.per : size
            var start = 0
            for member in ordered(taken + (own ? [0] : []), along: false) {
                let length = own && member == 0 ? shape.span : 1
                defer { start += length }
                guard let member else { continue }
                let along = (Double(group) / Double(groups), Double(group + 1) / Double(groups))
                let across = (Double(start) / Double(parts), Double(start + length) / Double(parts))
                result.append((member, rows
                    ? Cell(minX: across.0, maxX: across.1, minY: along.0, maxY: along.1)
                    : Cell(minX: along.0, maxX: along.1, minY: across.0, maxY: across.1)))
            }
        }
        return result
    }
}
