import Foundation

/// The point of a window that stays put while it resizes (spec v2).
public enum Anchor: String, CaseIterable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
}

/// Which way `step` goes through the widths.
public enum ResizeStep: String, CaseIterable, Sendable {
    case grow, shrink
}

/// Resize Window (S-065, S-067): to a size, by points, or a step through widths.
public struct ResizeAction: ActionValue {
    public enum Change: Sendable, Equatable {
        /// Fractions of the usable area.
        case to(width: Double, height: Double)
        /// Points.
        case by(dw: Double, dh: Double)
        /// nil widths are the default list.
        case step(ResizeStep, widths: [Double]?)
    }

    public var change: Change
    /// Used with `to` and `by` only.
    public var anchor: Anchor

    public init(_ change: Change, anchor: Anchor = .topLeft) {
        self.change = change
        self.anchor = anchor
    }

    /// The widths `step` goes through when the action has none.
    public static let defaultWidths = [1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4]

    public static let kinds = [ActionKind(type: "window.resize", displayName: "Resize Window")]

    public var type: String { "window.resize" }

    public static func blank(_ type: String) -> ResizeAction {
        ResizeAction(.step(.grow, widths: nil))
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["to", "by", "step", "anchor", "widths"])
        let which = try fields.one(of: ["to", "by", "step"])
        if which == "step" {
            if fields.has("anchor") { throw fields.conflict("anchor", with: "step") }
            let widths: [Double]? = try fields.optional("widths")
            if let widths {
                if widths.isEmpty { throw fields.badFraction("widths", "Add at least one width") }
                if widths.contains(where: { !($0 > 0 && $0 <= 1) }) {
                    throw fields.badFraction("widths", "Each width must be above 0 and at most 1")
                }
            }
            change = .step(try fields.choice("step")!, widths: widths)
            anchor = .topLeft
            return
        }
        if fields.has("widths") { throw fields.conflict("widths", with: which) }
        anchor = try fields.choice("anchor") ?? .topLeft
        if which == "to" {
            let to = try fields.numbers("to", required: ["width", "height"])!
            for name in ["width", "height"] where !(to[name]! > 0 && to[name]! <= 1) {
                throw fields.badFraction("to", "“\(name)” must be above 0 and at most 1")
            }
            change = .to(width: to["width"]!, height: to["height"]!)
        } else {
            let by = try fields.numbers("by", required: [], others: ["dw", "dh"])!
            change = .by(dw: by["dw"] ?? 0, dh: by["dh"] ?? 0)
        }
    }

    public func write(to fields: inout ActionFieldWriter) {
        switch change {
        case let .to(width, height):
            fields.numbers("to", [("width", width), ("height", height)])
        case let .by(dw, dh):
            fields.numbers("by", [("dw", dw), ("dh", dh)].filter { $0.1 != 0 })
        case let .step(step, widths):
            fields.string("step", step.rawValue)
            if let widths { fields.numberList("widths", widths) }
        }
        if anchor != .topLeft, !isStep { fields.string("anchor", anchor.rawValue) }
    }

    private var isStep: Bool {
        if case .step = change { true } else { false }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "to": WindowSchema.object(["width": WindowSchema.size, "height": WindowSchema.size], required: ["width", "height"]),
            "by": WindowSchema.object(["dw": WindowSchema.points, "dh": WindowSchema.points], required: []),
            "step": ["enum": ResizeStep.allCases.map(\.rawValue)],
            "anchor": ["enum": Anchor.allCases.map(\.rawValue),
                       "description": "The point that stays put with to and by. Default topLeft."],
            "widths": ["type": "array", "minItems": 1, "items": WindowSchema.size,
                       "description": "The widths step goes through. Default 1/4, 1/3, 1/2, 2/3, 3/4."],
        ])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.resize(change, anchor: anchor)))
    }
}
