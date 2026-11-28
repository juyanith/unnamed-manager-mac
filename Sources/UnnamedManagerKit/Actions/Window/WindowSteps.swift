import CoreGraphics

/// A count of steps across and down (spec v24, Steps): how many equal parts
/// cut a display's usable area, or the smallest cell Arrange Windows makes.
/// Values stay as written, so the validator can name one out of range.
public struct WindowSteps: Sendable, Hashable, CustomStringConvertible {
    public var across: Int
    public var down: Int

    /// The numbers `across` and `down` take.
    public static let range = 1...96

    public init(across: Int, down: Int) {
        self.across = across
        self.down = down
    }

    /// The guess from the display's shape: the short side gets 12, the
    /// long side 12 for each whole time the short side fits into it. The
    /// shape is the display's whole frame, not its usable area.
    public static func guess(for display: CGSize) -> WindowSteps {
        let long = max(display.width, display.height), short = max(1, min(display.width, display.height))
        let longSteps = 12 * max(1, Int((long / short).rounded(.down)))
        return display.width >= display.height ? WindowSteps(across: longSteps, down: 12) : WindowSteps(across: 12, down: longSteps)
    }

    /// Both counts in `range`, for a value the validator hasn't checked.
    public var clamped: WindowSteps {
        WindowSteps(across: min(max(across, Self.range.lowerBound), Self.range.upperBound),
                    down: min(max(down, Self.range.lowerBound), Self.range.upperBound))
    }

    public var description: String { "\(across) × \(down)" }
}

extension WindowSteps: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.rejectUnknown(allowed: ["across", "down"], at: "a steps object")
        across = try c.required("across")
        down = try c.required("down")
    }
}
