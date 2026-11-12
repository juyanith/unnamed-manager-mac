import CoreGraphics

/// The geometry the window actions share (spec v2, Window actions). Every
/// frame is in top-left coordinates: the origin is the top left of the main
/// display, and y grows down, as Accessibility reports windows.
public enum WindowGeometry {
    /// One display: its whole frame, and its usable area without the menu bar and Dock.
    public struct Screen: Sendable, Equatable {
        public var frame: CGRect
        public var usable: CGRect

        public init(frame: CGRect, usable: CGRect) {
            self.frame = frame
            self.usable = usable
        }
    }

    /// How close two edges must be to count as the same (spec: 2 points).
    public static let tolerance: CGFloat = 2

    /// A Cocoa rect (origin at the bottom left, y up) in top-left coordinates.
    /// `primaryHeight` is the height of the main display, the one at the origin.
    public static func topLeft(_ cocoa: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    /// The screen that holds the largest part of the window, or the first
    /// (the main display) when the window is on none.
    public static func screen(for window: CGRect, among screens: [Screen]) -> Screen? {
        func area(_ screen: Screen) -> CGFloat {
            let overlap = screen.frame.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = screens.max(by: { area($0) < area($1) }), area(best) > 0 else { return screens.first }
        return best
    }

    /// A frame in fractions as a rect in the usable area. Edges round to
    /// whole points, and sizes follow, so neighbours share an edge.
    public static func rect(_ fractions: FractionFrame, in usable: CGRect) -> CGRect {
        let left = (fractions.x * usable.width).rounded(), right = ((fractions.x + fractions.width) * usable.width).rounded()
        let top = (fractions.y * usable.height).rounded(), bottom = ((fractions.y + fractions.height) * usable.height).rounded()
        return CGRect(x: usable.minX + left, y: usable.minY + top,
                      width: min(right, usable.width) - left, height: min(bottom, usable.height) - top)
    }

    /// Where a window that took `size` instead of the target's size goes:
    /// on each axis it keeps the edge the target shares with the usable
    /// area, or its center when it shares neither or both.
    public static func anchored(_ size: CGSize, to target: CGRect, in usable: CGRect) -> CGRect {
        func origin(_ min: CGFloat, _ max: CGFloat, _ areaMin: CGFloat, _ areaMax: CGFloat, _ length: CGFloat) -> CGFloat {
            let atMin = abs(min - areaMin) <= tolerance, atMax = abs(max - areaMax) <= tolerance
            if atMin && !atMax { return min }
            if atMax && !atMin { return max - length }
            if atMin && atMax { return min }
            return ((min + max - length) / 2).rounded()
        }
        return CGRect(x: origin(target.minX, target.maxX, usable.minX, usable.maxX, size.width),
                      y: origin(target.minY, target.maxY, usable.minY, usable.maxY, size.height),
                      width: size.width, height: size.height)
    }

    /// Whether every edge of `a` is within the tolerance of the same edge of `b`.
    public static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }
}

/// What Maximize does next for one window, and the frame it had before
/// (S-062). Kept per window, in memory only.
public struct MaximizeMemory<Window: Hashable> {
    public enum Step: Equatable {
        /// Fill the usable area.
        case fill(CGRect)
        /// Go back to the frame from before Maximize.
        case restore(CGRect)
        /// Leave the window as it is.
        case stay
    }

    private var saved: [Window: (before: CGRect, after: CGRect)] = [:]

    public init() {}

    /// The next step for a window at `frame` on a screen with `usable` area.
    /// A window that moved or resized since Maximize forgets its old frame.
    public mutating func step(for window: Window, frame: CGRect, usable: CGRect, toggle: Bool) -> Step {
        let filled = WindowGeometry.matches(frame, usable)
        if let memory = saved[window] {
            if filled || WindowGeometry.matches(frame, memory.after) {
                guard toggle else { return .stay }
                saved[window] = nil
                return .restore(memory.before)
            }
            saved[window] = nil
        }
        return filled ? .stay : .fill(usable)
    }

    /// Remembers a window's frame from before Maximize, and the frame it
    /// took, which can differ from the usable area for an app that snaps
    /// its size (a terminal's character grid).
    public mutating func record(_ window: Window, before: CGRect, after: CGRect) {
        saved[window] = (before, after)
    }
}
