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
/// (spec v8). Pure, so both the app and the tests can ask it.
public enum ArrangeGrid {
    /// One cell, as fractions of the usable area. Neighbours get the same
    /// value for the edge they share, so they round to the same point.
    public struct Cell: Sendable, Equatable {
        public var minX: Double, maxX: Double, minY: Double, maxY: Double
        /// Which column or row it's in, and how many cells that group has.
        public var group: Int
        public var groupSize: Int

        /// The cell in the usable area, before the gap. Edges round to whole points.
        public func rect(in usable: CGRect) -> CGRect {
            let left = (minX * usable.width).rounded(), right = (maxX * usable.width).rounded()
            let top = (minY * usable.height).rounded(), bottom = (maxY * usable.height).rounded()
            return CGRect(x: usable.minX + left, y: usable.minY + top, width: right - left, height: bottom - top)
        }
    }

    /// `count` cells in `groups` columns, or rows. Extra cells go to the
    /// leftmost columns or the bottom rows, so the roomiest cells are on
    /// the right and at the top. Columns come left to right with their
    /// cells top to bottom; rows come top to bottom with theirs left to right.
    public static func cells(count: Int, groups: Int, rows: Bool) -> [Cell] {
        let groups = max(1, min(groups, count)), base = count / groups, extra = count % groups
        var cells: [Cell] = []
        for group in 0..<groups {
            let size = base + ((rows ? group >= groups - extra : group < extra) ? 1 : 0)
            for index in 0..<size {
                let along = (Double(group) / Double(groups), Double(group + 1) / Double(groups))
                let across = (Double(index) / Double(size), Double(index + 1) / Double(size))
                cells.append(rows
                    ? Cell(minX: across.0, maxX: across.1, minY: along.0, maxY: along.1, group: group, groupSize: size)
                    : Cell(minX: along.0, maxX: along.1, minY: across.0, maxY: across.1, group: group, groupSize: size))
            }
        }
        return cells
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
        // The best cells first: roomier, then further right, then further up.
        let best = cells(count: count, groups: groups, rows: rows).sorted {
            ($0.groupSize, -$0.maxX, $0.minY) < ($1.groupSize, -$1.maxX, $1.minY)
        }.prefix(used.count)
        guard let first = best.first else { return [] }
        if best.allSatisfy({ $0.groupSize == first.groupSize }) {
            return inOrder(used, windows, into: Array(best), rows: rows)
        }
        return [(0, first)] + inOrder(Array(used.dropFirst()), windows, into: Array(best.dropFirst()), rows: rows)
    }

    /// Windows keep the order they're in: sorted along the groups and dealt
    /// into them, then sorted across each group. Centers within the
    /// tolerance are the same; what's still tied goes by use, the window
    /// used more recently further right, or further up.
    private static func inOrder(_ indices: [Int], _ windows: [CGRect], into cells: [Cell], rows: Bool) -> [(window: Int, cell: Cell)] {
        func before(_ a: Int, _ b: Int, along: Bool) -> Bool {
            let byX = along != rows
            let first: (CGRect) -> CGFloat = byX ? \.midX : \.midY
            let second: (CGRect) -> CGFloat = byX ? \.midY : \.midX
            for key in [first, second] where abs(key(windows[a]) - key(windows[b])) > WindowGeometry.tolerance {
                return key(windows[a]) < key(windows[b])
            }
            return byX ? a > b : a < b
        }
        var rest = indices.sorted { before($0, $1, along: true) }[...]
        var result: [(window: Int, cell: Cell)] = []
        for group in Set(cells.map(\.group)).sorted() {
            let places = cells.filter { $0.group == group }.sorted { rows ? $0.minX < $1.minX : $0.minY < $1.minY }
            let members = rest.prefix(places.count).sorted { before($0, $1, along: false) }
            rest = rest.dropFirst(places.count)
            result += zip(members, places).map { ($0, $1) }
        }
        return result
    }
}
