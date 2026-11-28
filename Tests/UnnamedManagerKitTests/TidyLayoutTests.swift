import CoreGraphics
import Testing
@testable import UnnamedManagerKit

@Suite("Tidy Windows prototype (proposal)")
struct TidyLayoutTests {
    /// A 57" display at 3840 by 1080 points, with a 25 point menu bar.
    static let wide = CGRect(x: 0, y: 25, width: 3840, height: 1055)
    static let steps = TidyLayout.Steps(across: 36, down: 12)

    func tidy(_ windows: [CGRect], usable: CGRect = wide, steps: TidyLayout.Steps = steps) -> TidyLayout.Plan {
        TidyLayout.plan(usable: usable, steps: steps, windows: windows)
    }

    @Test("Steps are guessed from the display's shape")
    func guess() {
        #expect(TidyLayout.Steps.guess(for: CGSize(width: 3840, height: 1080)) == .init(across: 36, down: 12))
        #expect(TidyLayout.Steps.guess(for: CGSize(width: 3440, height: 1440)) == .init(across: 24, down: 12))
        #expect(TidyLayout.Steps.guess(for: CGSize(width: 1512, height: 982)) == .init(across: 12, down: 12))
        #expect(TidyLayout.Steps.guess(for: CGSize(width: 1920, height: 1080)) == .init(across: 12, down: 12))
        #expect(TidyLayout.Steps.guess(for: CGSize(width: 1080, height: 1920)) == .init(across: 12, down: 12))
    }

    @Test("A line may cross a quarter of a window, at least half a step and at most one")
    func allowance() {
        #expect(TidyLayout.allowance(length: 100, step: 160) == 80)
        #expect(TidyLayout.allowance(length: 400, step: 160) == 100)
        #expect(TidyLayout.allowance(length: 2000, step: 160) == 160)
    }

    @Test("Three windows roughly in thirds meet at the cuts")
    func thirds() {
        let plan = tidy([CGRect(x: 300, y: 60, width: 1000, height: 900),
                         CGRect(x: 1200, y: 30, width: 1400, height: 1000),
                         CGRect(x: 2700, y: 40, width: 1100, height: 1030)])
        #expect(plan.cuts.count == 2)
        #expect(plan.shared.isEmpty)
        let (a, b, c) = (plan.frames[0], plan.frames[1], plan.frames[2])
        #expect(a.maxX == b.minX)
        #expect(b.maxX == c.minX)
        // The layout has cuts, so the margin at the display's edge closes.
        #expect(a.minX == 0)
        // The right edge is within half a step of the display's edge.
        #expect(c.maxX == 3840)
    }

    @Test("A sliver over a neighbor still splits; a window put on top doesn't")
    func overlap() {
        let terminal = CGRect(x: 0, y: 25, width: 1300, height: 1055)
        let browser = CGRect(x: 1200, y: 25, width: 2640, height: 1055)
        let notes = CGRect(x: 2200, y: 200, width: 700, height: 500)
        let plan = tidy([notes, terminal, browser])
        #expect(plan.cuts.count == 1)
        #expect(plan.shared == [[0, 2]])
        // The browser fills its side; the notes window stays small, on steps.
        #expect(plan.frames[2].minX == plan.frames[1].maxX)
        #expect(plan.frames[2].maxX == 3840)
        #expect(plan.frames[0].width < 800)
    }

    @Test("A margin at the display's edge closes once there's a cut")
    func margins() {
        let plan = tidy([CGRect(x: 0, y: 25, width: 1900, height: 1055),
                         CGRect(x: 1950, y: 300, width: 1890, height: 780)])
        #expect(plan.frames[1].minY == 25)
        #expect(plan.frames[1].minX == plan.frames[0].maxX)
    }

    @Test("A lone window in the left half stays there")
    func lone() {
        let plan = tidy([CGRect(x: 10, y: 40, width: 1900, height: 1030)])
        #expect(plan.frames[0] == CGRect(x: 0, y: 25, width: 1920, height: 1055))
    }

    @Test("A column of two stacked windows beside a tall one")
    func mixed() {
        let plan = tidy([CGRect(x: 0, y: 25, width: 1250, height: 500),
                         CGRect(x: 20, y: 560, width: 1200, height: 500),
                         CGRect(x: 1300, y: 25, width: 2540, height: 1055)])
        #expect(plan.cuts.first?.axis == .vertical)
        #expect(plan.cuts.last?.axis == .horizontal)
        #expect(plan.frames[0].maxY == plan.frames[1].minY)
        #expect(plan.frames[0].maxX == plan.frames[2].minX)
        #expect(plan.frames[1].maxX == plan.frames[2].minX)
    }

    /// The 43" display the preview first ran on, 2026-11-27.
    static let square = CGRect(x: 0, y: 30, width: 3840, height: 2130)

    @Test("A window in front of both halves floats out of the cut")
    func floating() {
        let ghostty = CGRect(x: 2290, y: 1124, width: 1062, height: 957)
        let claude = CGRect(x: 760, y: 561, width: 2552, height: 1412)
        let right = CGRect(x: 1928, y: 38, width: 1904, height: 2114)
        let left = CGRect(x: 8, y: 38, width: 1904, height: 2114)
        let plan = tidy([ghostty, claude, right, right, right, left], usable: Self.square,
                        steps: .init(across: 12, down: 12))
        #expect(plan.cuts.first?.axis == .vertical)
        #expect(plan.floating == [1])
        // The halves stay halves; Claude stays exactly where it is.
        #expect(plan.frames[5] == CGRect(x: 0, y: 30, width: 1920, height: 2130))
        #expect(plan.frames[2] == CGRect(x: 1920, y: 30, width: 1920, height: 2130))
        #expect(plan.frames[1] == claude)
    }

    @Test("A window behind others still stops a line")
    func behind() {
        // A big window at the back, with two small ones in front of it.
        let plan = tidy([CGRect(x: 200, y: 100, width: 600, height: 400),
                         CGRect(x: 2600, y: 100, width: 600, height: 400),
                         CGRect(x: 100, y: 40, width: 3600, height: 1000)])
        #expect(plan.cuts.isEmpty)
        #expect(plan.floating.isEmpty)
    }

    @Test("Two windows that overlap a little are split halfway between")
    func halfway() {
        // The second preview on the 43" display, 2026-11-27: three rough
        // columns, the left two stacked with 212 pt of overlap.
        let plan = tidy([CGRect(x: 2753, y: 1174, width: 1062, height: 957),
                         CGRect(x: 11, y: 967, width: 1438, height: 1170),
                         CGRect(x: 1461, y: 32, width: 1057, height: 1354),
                         CGRect(x: 8, y: 38, width: 1292, height: 1141),
                         CGRect(x: 1560, y: 1431, width: 734, height: 679),
                         CGRect(x: 2732, y: 191, width: 1088, height: 914)],
                        usable: Self.square, steps: .init(across: 12, down: 12))
        #expect(plan.shared.isEmpty)
        #expect(plan.floating.isEmpty)
        #expect(plan.cuts.count == 5)
        #expect(plan.frames[3].maxY == plan.frames[1].minY)
    }

    @Test("A small window wedged between two others floats instead of taking a strip")
    func squeezed() {
        // The third preview on the 43" display, 2026-11-27, with no rule
        // leaving Calculator out.
        let plan = tidy([CGRect(x: 2700, y: 178, width: 1115, height: 1953),
                         CGRect(x: 11, y: 967, width: 1511, height: 1170),
                         CGRect(x: 2245, y: 1198, width: 230, height: 408),
                         CGRect(x: 1560, y: 1431, width: 1100, height: 679),
                         CGRect(x: 1461, y: 32, width: 1057, height: 1354),
                         CGRect(x: 8, y: 38, width: 1292, height: 1141),
                         CGRect(x: 2732, y: 191, width: 1088, height: 914)],
                        usable: Self.square, steps: .init(across: 12, down: 12))
        #expect(plan.floating == [2])
        // Calculator stays exactly where it is; Chrome meets Safari.
        #expect(plan.frames[2] == CGRect(x: 2245, y: 1198, width: 230, height: 408))
        #expect(plan.frames[4].maxY == plan.frames[3].minY)
    }

    @Test("A small window in empty space floats instead of growing into a cell")
    func grown() {
        // The fourth preview on the 43" display, 2026-11-27, with no rule
        // leaving Calculator out: it would have grown to 952 by 524.
        let calculator = CGRect(x: 2245, y: 1198, width: 230, height: 408)
        let plan = tidy([CGRect(x: 2697, y: 1033, width: 1115, height: 1104),
                         CGRect(x: 11, y: 967, width: 1511, height: 1170),
                         CGRect(x: 2697, y: 67, width: 1088, height: 914),
                         CGRect(x: 1461, y: 32, width: 1057, height: 922),
                         CGRect(x: 8, y: 38, width: 1416, height: 910),
                         calculator,
                         CGRect(x: 1560, y: 1431, width: 1100, height: 679)],
                        usable: Self.square, steps: .init(across: 12, down: 12))
        #expect(plan.floating == [5])
        #expect(plan.frames[5] == calculator)
        // Safari takes the space under Chrome.
        #expect(plan.frames[6].minY == plan.frames[3].maxY)
    }

    @Test("Tidying a tidy layout changes nothing")
    func repeatable() {
        let windows = [CGRect(x: 300, y: 60, width: 1000, height: 900),
                       CGRect(x: 1200, y: 30, width: 1400, height: 1000),
                       CGRect(x: 2200, y: 200, width: 700, height: 500),
                       CGRect(x: 2700, y: 40, width: 1100, height: 1030)]
        let once = tidy(windows).frames
        #expect(tidy(once).frames == once)
    }
}
