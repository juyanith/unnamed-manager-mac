import CoreGraphics

/// A window Focus Window and Swap Window can pick (spec v12): its frame,
/// the part of it you can see, and its app.
public struct SeenWindow: Sendable, Equatable {
    public var frame: CGRect
    /// The frame minus the windows in front of it, as rects that don't overlap.
    public var parts: [CGRect]
    /// The app's process id, which breaks ties in the order.
    public var owner: Int32

    /// With no `parts`, the whole frame shows.
    public init(frame: CGRect, parts: [CGRect]? = nil, owner: Int32 = 1) {
        self.frame = frame
        self.parts = parts ?? [frame]
        self.owner = owner
    }

    /// The box around the part you can see; the frame when none shows.
    public var box: CGRect {
        guard let first = parts.first else { return frame }
        return parts.dropFirst().reduce(first) { $0.union($1) }
    }
}

extension WindowGeometry {
    /// Each window's visible part, for windows front to back (spec v12): its
    /// frame minus every window in front of it.
    public static func visibleParts(_ frames: [CGRect]) -> [[CGRect]] {
        frames.indices.map { index in
            frames[..<index].reduce([frames[index]]) { parts, cover in
                parts.flatMap { subtract(cover, from: $0) }
            }
        }
    }

    /// `rect` without `cover`: up to four rects, above, below, left and right of it.
    static func subtract(_ cover: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cover)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    /// Whether `parts` hold a square `side` points on a side (`windows.minVisible`);
    /// with 0, whether any part shows.
    public static func shows(_ parts: [CGRect], square side: CGFloat) -> Bool {
        guard side > 0 else { return !parts.isEmpty }
        // A square that fits slides left and then up until it meets the left
        // and top edges of parts, so only those corners need trying.
        for x in parts.map(\.minX) {
            for y in parts.map(\.minY) {
                let square = CGRect(x: x, y: y, width: side, height: side)
                let covered = parts.reduce(CGFloat(0)) { sum, part in
                    let overlap = part.intersection(square)
                    return overlap.isNull ? sum : sum + overlap.width * overlap.height
                }
                if covered >= side * side * 0.9999 { return true }
            }
        }
        return false
    }

    /// A rect turned so `direction` points to growing x: left mirrors x,
    /// down swaps the axes, up does both. nil for a word that isn't a direction.
    static func turned(_ rect: CGRect, _ direction: FocusDirection) -> CGRect? {
        switch direction {
        case .right: rect
        case .left: CGRect(x: -rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        case .down: CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        case .up: CGRect(x: -rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .next, .previous, .first, .last: nil
        }
    }

    /// The length the intervals cover together.
    static func covered(_ spans: [ClosedRange<CGFloat>]) -> CGFloat {
        var total: CGFloat = 0, end = -CGFloat.infinity
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) where span.upperBound > end {
            total += span.upperBound - max(span.lowerBound, end)
            end = span.upperBound
        }
        return total
    }
}
