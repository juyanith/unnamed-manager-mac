import Testing
@testable import UnnamedManagerKit

@Suite("Last focused window (S-047)")
struct LastWindowTests {
    typealias W = LastWindow.Candidate<Int>

    @Test("The focused window wins, even when another window is on top")
    func focused() {
        #expect(LastWindow.pick(focused: 2, main: 1, windows: [W(id: 1), W(id: 2)]) == .init(id: 2, unminimize: false))
    }

    @Test("Without a focused window, the main window")
    func main() {
        #expect(LastWindow.pick(focused: nil, main: 3, windows: [W(id: 1), W(id: 3)]) == .init(id: 3, unminimize: false))
    }

    @Test("A focused id that isn't among the windows is ignored")
    func stale() {
        #expect(LastWindow.pick(focused: 9, main: nil, windows: [W(id: 1)]) == .init(id: 1, unminimize: false))
    }

    @Test("Otherwise the frontmost standard window, skipping panels and minimized ones")
    func frontmost() {
        let windows = [W(id: 1, isStandard: false), W(id: 2, isMinimized: true), W(id: 3)]
        #expect(LastWindow.pick(focused: nil, main: nil, windows: windows) == .init(id: 3, unminimize: false))
    }

    @Test("Only minimized windows: the first comes out of the Dock")
    func minimized() {
        let windows = [W(id: 1, isMinimized: true), W(id: 2, isMinimized: true)]
        #expect(LastWindow.pick(focused: nil, main: nil, windows: windows) == .init(id: 1, unminimize: true))
    }

    @Test("No windows, or only panels: nothing to raise")
    func none() {
        #expect(LastWindow.pick(focused: nil, main: nil, windows: [W]()) == nil)
        #expect(LastWindow.pick(focused: nil, main: nil, windows: [W(id: 1, isStandard: false)]) == nil)
    }
}
