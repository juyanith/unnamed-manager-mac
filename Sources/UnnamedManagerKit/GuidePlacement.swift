import CoreGraphics
import Foundation

/// Where the Guide goes (S-019): on the screen that holds the front app's
/// key window, at the configured position. Pure geometry in AppKit's
/// coordinates (origin at the bottom left of the primary screen).
public enum GuidePlacement {
    public enum Position: String, Sendable, CaseIterable {
        case center, top, bottom
    }

    /// How far the Guide sits from the top or bottom edge, as a share of
    /// the screen's visible height.
    public static let edgeInset: CGFloat = 0.2

    /// The index of the screen that holds most of `window`, or nil.
    public static func screen(for window: CGRect, in screens: [CGRect]) -> Int? {
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// A window's bounds from CGWindowList (origin at the top left of the
    /// primary screen) in AppKit's coordinates.
    public static func appKitRect(fromWindowList bounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: primaryScreenHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    /// The Guide's origin in a screen's visible frame, centered left to right.
    public static func origin(size: CGSize, in visible: CGRect, position: Position) -> CGPoint {
        let x = (visible.midX - size.width / 2).rounded()
        let y: CGFloat
        switch position {
        case .center: y = visible.midY - size.height / 2
        case .top: y = visible.maxY - visible.height * edgeInset - size.height
        case .bottom: y = visible.minY + visible.height * edgeInset
        }
        return CGPoint(x: x, y: y.rounded())
    }
}
