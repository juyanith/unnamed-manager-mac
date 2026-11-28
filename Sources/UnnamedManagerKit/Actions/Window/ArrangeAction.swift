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
    /// Every window on the display, up to the limits `windows.minCell` sets.
    case all
}

/// Arrange Windows (S-075, S-076): the windows used last, on the focused
/// window's display, in a grid of columns or rows.
public struct ArrangeAction: ActionValue {
    /// The numbers `count` and `groups` take. `"all"` may arrange more (spec v24).
    public static let countRange = 2...8
    public static let groupsRange = 1...8

    public var count: ArrangeCount
    /// nil lets the app pick, up to the limits `windows.minCell` sets.
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

    /// `window-arrange-2` is the same as `window-arrange`, so it isn't listed.
    public static func builtInValues(_ type: String) -> [String?] {
        [nil] + countRange.dropFirst().map { String($0) } + ["all"]
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "count": ["oneOf": [["type": "integer", "minimum": countRange.lowerBound, "maximum": countRange.upperBound], ["enum": ["all"]]],
                      "description": "How many windows: the focused one and the ones used before it. \"all\" is every window on the display, up to the most columns times the most rows that windows.minCell allows. Default 2."],
            "groups": ["type": "integer", "minimum": groupsRange.lowerBound, "maximum": groupsRange.upperBound,
                       "description": "How many columns or rows. Without it, as many as there are windows, up to the most that windows.minCell allows."],
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
    ///
    /// Cells land on the display's `steps` (spec v24): the groups share
    /// the steps along them, and each group's cells share its steps the
    /// other way, the leftover steps going one each from the left or the
    /// top. `minCell` sets the most columns and rows the app picks.
    /// `minimums` are the smallest sizes in points, by window, from each
    /// app's `minWidth` and `minHeight`.
    public static func plan(_ action: ArrangeAction, steps: WindowSteps, minCell: WindowSteps, usable: CGRect,
                            windows: [CGRect], minimums: [CGSize] = []) -> [(window: Int, cell: Cell)] {
        guard !windows.isEmpty else { return [] }
        let steps = steps.clamped, minCell = minCell.clamped
        let cell = WindowSteps(across: min(minCell.across, steps.across), down: min(minCell.down, steps.down))
        let maxColumns = max(1, steps.across / cell.across), maxRows = max(1, steps.down / cell.down)
        let count = switch action.count {
        case let .windows(number): number
        case .all: max(1, min(windows.count, maxColumns * maxRows))
        }
        let rows = action.layout == .rows || (action.layout == .auto && usable.height > usable.width)
        let used = Array(windows.indices.prefix(count))
        // Along the groups, and across one.
        let alongSteps = rows ? steps.down : steps.across, acrossSteps = rows ? steps.across : steps.down
        let floor = rows ? cell.down : cell.across

        /// The steps a window needs, along the groups or across one.
        func need(_ window: Int, along: Bool) -> Int {
            guard window < minimums.count else { return 0 }
            let byWidth = along != rows
            let points = byWidth ? minimums[window].width : minimums[window].height
            let total = along ? alongSteps : acrossSteps
            let step = (byWidth ? usable.width : usable.height) / CGFloat(total)
            guard points > 0, step > 0 else { return 0 }
            return min(total, Int((points / step - 0.000_001).rounded(.up)))
        }

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

        /// The grid in `groups` groups, or nil when a window's smallest
        /// size leaves the other groups less than `minCell`.
        func layout(_ groups: Int) -> [(window: Int, cell: Cell)]? {
            // The focused window stays in the group its center is in, by the groups' steps.
            let center = rows ? (windows[0].midY - usable.minY) / usable.height : (windows[0].midX - usable.minX) / usable.width
            let plain = bounds(alongSteps, spans: Array(repeating: 1, count: groups), needs: [], floor: 1) ?? [0, 1]
            let home = center.isFinite ? max(0, (plain.dropFirst().firstIndex { Double(center) < $0 } ?? groups) - 1) : 0
            let shape = shape(count: count, groups: groups, rows: rows, focused: home)
            var order = ordered(used + Array(repeating: nil, count: count - used.count), along: true)
            // The focused window is dealt into its own group; the others fill the groups in order.
            if shape.focused != nil { order.removeAll { $0 == 0 } }
            var rest = order[...]
            // Each group's members across it, with how many of its cells each spans.
            var members: [[(window: Int?, span: Int)]] = []
            for (group, size) in shape.sizes.enumerated() {
                let own = group == shape.focused
                let taken = rest.prefix(own ? size - 1 : size)
                rest = rest.dropFirst(taken.count)
                // The focused window's group keeps the plain grid's cells; another group splits equally.
                members.append(ordered(taken + (own ? [0] : []), along: false).map { ($0, own && $0 == 0 ? shape.span : 1) })
            }
            let groupNeeds = members.map { $0.compactMap(\.window).map { need($0, along: true) }.max() ?? 0 }
            guard let along = bounds(alongSteps, spans: Array(repeating: 1, count: groups), needs: groupNeeds, floor: floor) else {
                return nil
            }
            var result: [(window: Int, cell: Cell)] = []
            for (group, list) in members.enumerated() {
                let needs = list.map { $0.window.map { need($0, along: false) } ?? 0 }
                let spans = list.map(\.span)
                let across = bounds(acrossSteps, spans: spans, needs: needs, floor: 1)
                    ?? bounds(acrossSteps, spans: spans, needs: [], floor: 1)!
                for (index, member) in list.enumerated() {
                    guard let window = member.window else { continue }
                    let a = (along[group], along[group + 1]), b = (across[index], across[index + 1])
                    result.append((window, rows
                        ? Cell(minX: b.0, maxX: b.1, minY: a.0, maxY: a.1)
                        : Cell(minX: a.0, maxX: a.1, minY: b.0, maxY: b.1)))
                }
            }
            return result
        }

        var groups = min(count, max(1, action.groups ?? (rows ? maxRows : maxColumns)))
        while groups > 1, layout(groups) == nil { groups -= 1 }
        return layout(groups) ?? []
    }

    /// Where members' cells start and end, as fractions, for members that
    /// span `spans` cells each over `total` steps. Each cell gets the steps
    /// divided by the cells, rounded down, and the leftover steps go one
    /// each from the start. A member that `needs` more steps gets them,
    /// from the others, which keep at least `floor` steps a cell; nil when
    /// they can't. With fewer steps than cells, the cells split equally.
    static func bounds(_ total: Int, spans: [Int], needs: [Int], floor: Int) -> [Double]? {
        let cells = spans.reduce(0, +)
        guard cells > 0 else { return [0] }
        func edges(_ sizes: [Int]) -> [Double] {
            sizes.reduce(into: [0]) { $0.append($0.last! + $1) }.map { Double($0) / Double(total) }
        }
        guard total >= cells else {
            var start = 0
            return [0] + spans.map { span in start += span; return Double(start) / Double(cells) }
        }
        /// `steps` over `cells` cells, each member the sum of its cells.
        func share(_ steps: Int, _ spans: [Int]) -> [Int] {
            let count = spans.reduce(0, +), base = steps / max(1, count), extra = steps % max(1, count)
            var cell = 0
            return spans.map { span in
                defer { cell += span }
                return (cell..<cell + span).reduce(0) { $0 + base + ($1 < extra ? 1 : 0) }
            }
        }
        var sizes = share(total, spans)
        var fixed = Set<Int>()
        while true {
            let short = sizes.indices.filter { !fixed.contains($0) && $0 < needs.count && sizes[$0] < needs[$0] }
            if short.isEmpty { return edges(sizes) }
            fixed.formUnion(short)
            let others = sizes.indices.filter { !fixed.contains($0) }
            let taken = fixed.reduce(0) { $0 + min(needs[$1], total) }
            let room = total - taken
            if others.isEmpty {
                guard room >= 0 else { return nil }
                // Every member is fixed: the steps left over go one each from the start.
                let extra = share(room, Array(repeating: 1, count: sizes.count))
                return edges(sizes.indices.map { min(needs[$0], total) + extra[$0] })
            }
            let otherSpans = others.map { spans[$0] }
            guard room >= otherSpans.reduce(0, +) * floor else { return nil }
            let shared = share(room, otherSpans)
            for index in fixed { sizes[index] = min(needs[index], total) }
            for (index, size) in zip(others, shared) { sizes[index] = size }
        }
    }
}
