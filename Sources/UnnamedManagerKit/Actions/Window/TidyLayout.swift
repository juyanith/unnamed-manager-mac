import CoreGraphics

/// Tidy Windows (spec v24, `window.tidy`): finds the straight cuts that
/// split the windows on a display into columns and rows, and snaps every
/// edge to the display's steps. Pure geometry, so the app and the tests
/// can both ask it.
public enum TidyLayout {
    /// How many steps split the usable area, across and down.
    public typealias Steps = WindowSteps

    /// One cut the layout found, for the report.
    public struct Cut: Sendable, Equatable {
        public enum Axis: String, Sendable { case vertical, horizontal }
        public var axis: Axis
        /// The step the line is on, counted from the left or the top of the usable area.
        public var step: Int
        /// Where the line starts and ends, in steps along the other axis.
        public var start: Int, end: Int
        /// How deep in the tree: 0 for the first cut.
        public var depth: Int
        /// The windows on each side, by index.
        public var before: [Int], after: [Int]
        /// Points of windows the line crosses, summed.
        public var crossing: CGFloat
        /// Windows in front of windows on both sides, set aside for this cut.
        public var floating: [Int]
    }

    /// The result: a frame for each window by index (without the gap), the
    /// cuts in the order found, the groups no line split, and the windows
    /// that floated out of a cut.
    public struct Plan: Sendable {
        public var frames: [CGRect]
        public var cuts: [Cut]
        public var shared: [[Int]]
        public var floating: [Int]

        public init(frames: [CGRect], cuts: [Cut], shared: [[Int]], floating: [Int]) {
            (self.frames, self.cuts, self.shared, self.floating) = (frames, cuts, shared, floating)
        }
    }

    /// An area in steps, and which of its sides windows reach: a cut, or,
    /// once the layout has a cut, the usable area's edge. A side that isn't
    /// reached just snaps, so a lone window keeps its margin.
    private struct Area {
        var x0, x1, y0, y1: Int
        var cutLeft = false, cutRight = false, cutTop = false, cutBottom = false
    }

    private struct Grid {
        let usable: CGRect
        let steps: Steps
        /// The smallest cell, which the window across a cut keeps when a cut moves for an app's smallest size.
        let minCell: Steps
        /// Each window's smallest size, in steps across and down.
        let needs: [(across: Int, down: Int)]
        var stepWidth: CGFloat { usable.width / CGFloat(steps.across) }
        var stepHeight: CGFloat { usable.height / CGFloat(steps.down) }
        func x(_ step: Int) -> CGFloat { usable.minX + (CGFloat(step) * stepWidth).rounded() }
        func y(_ step: Int) -> CGFloat { usable.minY + (CGFloat(step) * stepHeight).rounded() }
        func nearestX(_ value: CGFloat) -> Int { Int(((value - usable.minX) / stepWidth).rounded()) }
        func nearestY(_ value: CGFloat) -> Int { Int(((value - usable.minY) / stepHeight).rounded()) }
    }

    /// `windows` are front to back, as the platform lists them. The order
    /// decides which windows float out of a cut: a window in front of
    /// windows on both sides of a line doesn't stop it.
    /// `minimums` are the smallest sizes in points, by window, from each
    /// app's `minWidth` and `minHeight`; `minCell` is what the window on
    /// the other side of a cut keeps when the cut moves for one.
    public static func plan(usable: CGRect, steps: Steps, windows: [CGRect], minimums: [CGSize] = [],
                            minCell: Steps = Config.Windows.standardMinCell) -> Plan {
        let steps = steps.clamped
        let stepWidth = usable.width / CGFloat(steps.across), stepHeight = usable.height / CGFloat(steps.down)
        func need(_ points: CGFloat, _ step: CGFloat, _ total: Int) -> Int {
            points > 0 && step > 0 ? min(total, Int((points / step - 0.000_001).rounded(.up))) : 0
        }
        let needs = windows.indices.map { i in
            i < minimums.count ? (need(minimums[i].width, stepWidth, steps.across), need(minimums[i].height, stepHeight, steps.down)) : (0, 0)
        }
        let cell = minCell.clamped
        let grid = Grid(usable: usable, steps: steps, minCell: Steps(across: min(cell.across, steps.across), down: min(cell.down, steps.down)),
                        needs: needs)
        // Only the part of each window on the usable area counts.
        let clipped = windows.map { frame -> CGRect in
            let part = frame.intersection(usable)
            return part.isNull ? CGRect(origin: CGPoint(x: usable.midX, y: usable.midY), size: .zero) : part
        }
        let whole = Area(x0: 0, x1: steps.across, y0: 0, y1: steps.down)
        // A window its area would make less than half or more than twice its
        // width or height floats instead, and the layout is found again
        // without it: a small window wedged between two others doesn't get a
        // strip, and one left in empty space isn't blown up to fill it.
        var squeezed: [Int] = []
        while true {
            var plan = Plan(frames: windows, cuts: [], shared: [], floating: [])
            let taking = windows.indices.filter { !squeezed.contains($0) }
            if !taking.isEmpty {
                split(taking, in: whole, depth: 0, frames: clipped, grid: grid, plan: &plan)
            }
            let more = taking.filter { i in
                !plan.floating.contains(i) && clipped[i].width > 0
                    && (plan.frames[i].width < clipped[i].width / 2 || plan.frames[i].height < clipped[i].height / 2
                        || plan.frames[i].width > clipped[i].width * 2 || plan.frames[i].height > clipped[i].height * 2)
            }
            if more.isEmpty || more.count == taking.count {
                // Floating windows stay exactly where they are (plan.frames starts as the windows' frames).
                plan.floating += squeezed
                return plan
            }
            squeezed += more
        }
    }

    /// How far a line may cross a window: a quarter of it, at least half a
    /// step and at most one step.
    static func allowance(length: CGFloat, step: CGFloat) -> CGFloat {
        min(step, max(length / 4, step / 2))
    }

    private struct Candidate {
        var axis: Cut.Axis
        var before: [Int], after: [Int]
        var step: Int
        var crossing: CGFloat
        /// The crossing in steps, so the two axes compare fairly.
        var cost: CGFloat
        var floating: [Int]
    }

    private static func split(_ group: [Int], in area: Area, depth: Int, frames: [CGRect], grid: Grid, plan: inout Plan) {
        if group.count > 1, var cut = bestCut(group, in: area, frames: frames, grid: grid) {
            cut.step = room(for: cut, in: area, grid: grid)
            // A layout with a cut fills the display: margins at its edges close.
            var area = area
            if depth == 0 { (area.cutLeft, area.cutRight, area.cutTop, area.cutBottom) = (true, true, true, true) }
            let (start, end) = cut.axis == .vertical ? (area.y0, area.y1) : (area.x0, area.x1)
            plan.cuts.append(Cut(axis: cut.axis, step: cut.step, start: start, end: end, depth: depth,
                                 before: cut.before, after: cut.after, crossing: cut.crossing, floating: cut.floating))
            // A floating window stays exactly where it is, in front.
            plan.floating += cut.floating
            var first = area, second = area
            if cut.axis == .vertical {
                first.x1 = cut.step; first.cutRight = true
                second.x0 = cut.step; second.cutLeft = true
            } else {
                first.y1 = cut.step; first.cutBottom = true
                second.y0 = cut.step; second.cutTop = true
            }
            split(cut.before, in: first, depth: depth + 1, frames: frames, grid: grid, plan: &plan)
            split(cut.after, in: second, depth: depth + 1, frames: frames, grid: grid, plan: &plan)
            return
        }
        if group.count > 1 { plan.shared.append(group) }
        snap(group, in: area, frames: frames, grid: grid, plan: &plan)
    }

    /// A cut that would make a window smaller than its app's smallest
    /// size moves away from it, as long as the windows on the other side
    /// keep at least `minCell`. Otherwise it stays where it fell.
    private static func room(for cut: Candidate, in area: Area, grid: Grid) -> Int {
        let vertical = cut.axis == .vertical
        let lo = vertical ? area.x0 : area.y0, hi = vertical ? area.x1 : area.y1
        let floor = max(1, vertical ? grid.minCell.across : grid.minCell.down)
        func need(_ side: [Int]) -> Int { side.map { vertical ? grid.needs[$0].across : grid.needs[$0].down }.max() ?? 0 }
        var at = cut.step
        if at - lo < need(cut.before), hi - (lo + need(cut.before)) >= floor { at = lo + need(cut.before) }
        if hi - at < need(cut.after), (hi - need(cut.after)) - lo >= floor { at = hi - need(cut.after) }
        return min(hi - 1, max(lo + 1, at))
    }

    /// The line that crosses the least, of those that work on either axis.
    /// A tie goes to the vertical line on a wide display, the horizontal one
    /// on a tall display.
    private static func bestCut(_ group: [Int], in area: Area, frames: [CGRect], grid: Grid) -> Candidate? {
        let vertical = candidates(group, axis: .vertical, in: area, frames: frames, grid: grid)
        let horizontal = candidates(group, axis: .horizontal, in: area, frames: frames, grid: grid)
        let wide = grid.usable.width >= grid.usable.height
        let all = wide ? vertical + horizontal : horizontal + vertical
        // Fewer windows set aside first, then the least crossing.
        return all.min { ($0.floating.count, $0.cost) < ($1.floating.count, $1.cost - 0.001) }
    }

    private static func candidates(_ group: [Int], axis: Cut.Axis, in area: Area, frames: [CGRect], grid: Grid) -> [Candidate] {
        let vertical = axis == .vertical
        let step = vertical ? grid.stepWidth : grid.stepHeight
        func low(_ i: Int) -> CGFloat { vertical ? frames[i].minX : frames[i].minY }
        func high(_ i: Int) -> CGFloat { vertical ? frames[i].maxX : frames[i].maxY }
        // Lines worth trying: every window's edges, and halfway between one
        // window's far edge and another's near edge, so two windows that
        // overlap a little can each be crossed by half of it.
        let edges = group.flatMap { [low($0), high($0)] }
        let halfways = group.flatMap { i in group.map { j in (high(i) + low(j)) / 2 } }
        let lines = Set(edges + halfways).sorted()
        // For each way of splitting the group, the line that crosses least.
        var found: [[Int]: Candidate] = [:]
        for line in lines {
            var before: [Int] = [], after: [Int] = [], blocking: [Int] = [], crossing: CGFloat = 0
            for i in group {
                let ahead = max(0, high(i) - max(low(i), line)), behind = max(0, min(high(i), line) - low(i))
                let room = allowance(length: high(i) - low(i), step: step)
                if ahead <= room && (ahead <= behind || behind > room) {
                    before.append(i); crossing += ahead
                } else if behind <= room {
                    after.append(i); crossing += behind
                } else {
                    blocking.append(i)
                }
            }
            // A window the line crosses too far floats out of the cut when
            // it's in front of a window on each side; otherwise the line fails.
            func inFront(of side: [Int], _ i: Int) -> Bool {
                side.contains { $0 > i && frames[$0].intersects(frames[i]) }
            }
            guard blocking.allSatisfy({ inFront(of: before, $0) && inFront(of: after, $0) }),
                  !before.isEmpty, !after.isEmpty else { continue }
            let key = before.sorted()
            if let best = found[key], best.crossing <= crossing { continue }
            // Halfway between the groups' facing edges, on the nearest step inside the area.
            let edge = (before.map(high).max()! + after.map(low).min()!) / 2
            let lo = vertical ? area.x0 : area.y0, hi = vertical ? area.x1 : area.y1
            guard hi - lo >= 2 else { continue }
            let at = min(hi - 1, max(lo + 1, vertical ? grid.nearestX(edge) : grid.nearestY(edge)))
            found[key] = Candidate(axis: axis, before: before, after: after, step: at, crossing: crossing,
                                   cost: crossing / step, floating: blocking)
        }
        // In order of the split, so the choice between equal ones is the same every time.
        return found.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { found[$0]! }
    }

    /// A group no line splits: each window snaps its own edges to the
    /// nearest step. A side that faces a cut goes to the cut when the window
    /// reaches furthest that way in its group, so neighbors meet.
    private static func snap(_ group: [Int], in area: Area, frames: [CGRect], grid: Grid, plan: inout Plan) {
        let furthestLeft = group.map { frames[$0].minX }.min()!, furthestRight = group.map { frames[$0].maxX }.max()!
        let furthestUp = group.map { frames[$0].minY }.min()!, furthestDown = group.map { frames[$0].maxY }.max()!
        let tieX = grid.stepWidth / 2, tieY = grid.stepHeight / 2
        for i in group {
            let f = frames[i]
            var left = area.cutLeft && f.minX - furthestLeft <= tieX ? area.x0 : grid.nearestX(f.minX)
            var right = area.cutRight && furthestRight - f.maxX <= tieX ? area.x1 : grid.nearestX(f.maxX)
            var top = area.cutTop && f.minY - furthestUp <= tieY ? area.y0 : grid.nearestY(f.minY)
            var bottom = area.cutBottom && furthestDown - f.maxY <= tieY ? area.y1 : grid.nearestY(f.maxY)
            left = min(max(left, area.x0), area.x1 - 1); right = max(min(right, area.x1), left + 1)
            top = min(max(top, area.y0), area.y1 - 1); bottom = max(min(bottom, area.y1), top + 1)
            plan.frames[i] = CGRect(x: grid.x(left), y: grid.y(top), width: grid.x(right) - grid.x(left), height: grid.y(bottom) - grid.y(top))
        }
    }
}
