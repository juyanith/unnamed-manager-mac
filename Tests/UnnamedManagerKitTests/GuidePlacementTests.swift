import CoreGraphics
import Testing
@testable import UnnamedManagerKit

@Suite("Guide placement (S-019)")
struct GuidePlacementTests {
    // A 1440 x 900 laptop screen, and a 2560 x 1440 display to its right.
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -200, width: 2560, height: 1440)]

    @Test("The screen holding most of the front window wins, not the main screen")
    func screen() {
        #expect(GuidePlacement.screen(for: CGRect(x: 2000, y: 100, width: 800, height: 600), in: screens) == 1)
        #expect(GuidePlacement.screen(for: CGRect(x: 1300, y: 100, width: 300, height: 300), in: screens) == 1)
        #expect(GuidePlacement.screen(for: CGRect(x: 100, y: 100, width: 300, height: 300), in: screens) == 0)
        #expect(GuidePlacement.screen(for: CGRect(x: 9000, y: 0, width: 10, height: 10), in: screens) == nil)
    }

    @Test("Window list bounds flip to AppKit's coordinates")
    func flip() {
        let rect = GuidePlacement.appKitRect(fromWindowList: CGRect(x: 10, y: 0, width: 100, height: 50), primaryScreenHeight: 900)
        #expect(rect == CGRect(x: 10, y: 850, width: 100, height: 50))
    }

    @Test("Center, top and bottom sit in the visible frame")
    func positions() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = CGSize(width: 200, height: 100)
        #expect(GuidePlacement.origin(size: size, in: visible, position: .center) == CGPoint(x: 400, y: 450))
        #expect(GuidePlacement.origin(size: size, in: visible, position: .top) == CGPoint(x: 400, y: 700))
        #expect(GuidePlacement.origin(size: size, in: visible, position: .bottom) == CGPoint(x: 400, y: 200))
    }
}
