import Foundation

/// A frame as fractions of the usable area (spec v2).
public struct FractionFrame: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Place Window's presets (spec v2), as exact fractions so thirds line up.
public enum PlacePreset: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case center

    public var frame: FractionFrame {
        let third = 1.0 / 3, twoThirds = 2.0 / 3
        return switch self {
        case .leftHalf: FractionFrame(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: FractionFrame(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: FractionFrame(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: FractionFrame(x: 0, y: 0.5, width: 1, height: 0.5)
        case .leftThird: FractionFrame(x: 0, y: 0, width: third, height: 1)
        case .centerThird: FractionFrame(x: third, y: 0, width: third, height: 1)
        case .rightThird: FractionFrame(x: twoThirds, y: 0, width: third, height: 1)
        case .leftTwoThirds: FractionFrame(x: 0, y: 0, width: twoThirds, height: 1)
        case .rightTwoThirds: FractionFrame(x: third, y: 0, width: twoThirds, height: 1)
        case .topLeft: FractionFrame(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: FractionFrame(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: FractionFrame(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: FractionFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .center: FractionFrame(x: 1.0 / 6, y: 1.0 / 6, width: twoThirds, height: twoThirds)
        }
    }
}

/// Place Window (S-064): move and resize to a preset or a frame.
public enum PlaceAction: ActionValue {
    case preset(PlacePreset)
    case frame(FractionFrame)

    public static let kinds = [ActionKind(type: "window.place", displayName: "Place Window")]

    public var type: String { "window.place" }

    public static func blank(_ type: String) -> PlaceAction {
        .preset(.leftHalf)
    }

    /// A frame that adds up to 1 within this counts as 1.
    static let slack = 0.001

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["preset", "frame"])
        if try fields.one(of: ["preset", "frame"]) == "preset" {
            self = .preset(try fields.choice("preset")!)
            return
        }
        let f = try fields.numbers("frame", required: ["x", "y", "width", "height"])!
        let frame = FractionFrame(x: f["x"]!, y: f["y"]!, width: f["width"]!, height: f["height"]!)
        for (name, value) in [("x", frame.x), ("y", frame.y)] where !(0...1).contains(value) {
            throw fields.badFraction("frame", "“\(name)” must be from 0 to 1")
        }
        for (name, value) in [("width", frame.width), ("height", frame.height)] where !(value > 0 && value <= 1) {
            throw fields.badFraction("frame", "“\(name)” must be above 0 and at most 1")
        }
        if frame.x + frame.width > 1 + Self.slack || frame.y + frame.height > 1 + Self.slack {
            throw fields.badFraction("frame", "The frame runs past the usable area")
        }
        self = .frame(frame)
    }

    public func write(to fields: inout ActionFieldWriter) {
        switch self {
        case let .preset(preset):
            fields.string("preset", preset.rawValue)
        case let .frame(frame):
            fields.numbers("frame", [("x", frame.x), ("y", frame.y), ("width", frame.width), ("height", frame.height)])
        }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "preset": ["enum": PlacePreset.allCases.map(\.rawValue)],
            "frame": WindowSchema.object(["x": WindowSchema.fraction, "y": WindowSchema.fraction,
                                          "width": WindowSchema.size, "height": WindowSchema.size],
                                         required: ["x", "y", "width", "height"]),
        ])
    }

    public var fractions: FractionFrame {
        switch self {
        case let .preset(preset): preset.frame
        case let .frame(frame): frame
        }
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.place(fractions)))
    }
}
