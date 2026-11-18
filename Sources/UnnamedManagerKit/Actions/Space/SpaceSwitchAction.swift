import Foundation

/// Which way Switch Space goes (spec v17).
public enum SpaceDirection: String, CaseIterable, Sendable {
    case left, right

    public var displayName: String { rawValue.capitalized }
}

/// Switch Space (S-088, spec v17): go to the Space to the left or right on
/// the focused window's display, without the slide. Not a window action:
/// with no focused window it does nothing, and that isn't a failure.
public struct SpaceSwitchAction: ActionValue {
    public var target: SpaceDirection

    public init(_ target: SpaceDirection) {
        self.target = target
    }

    public static let kinds = [ActionKind(type: "space.switch", displayName: "Switch Space", symbol: "rectangle.3.group")]

    public var type: String { "space.switch" }

    public static func blank(_ type: String) -> SpaceSwitchAction {
        SpaceSwitchAction(.right)
    }

    /// `target` is required. Any other value, a number included, is `bad-window-value`.
    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target"])
        enum Raw: Decodable {
            case word(String), other

            init(from decoder: any Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let word = try? value.decode(String.self) {
                    self = .word(word)
                } else if (try? value.decode(Double.self)) != nil {
                    self = .other
                } else {
                    throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath,
                                                                        debugDescription: "Expected left or right."))
                }
            }
        }
        guard let raw: Raw = try fields.optional("target") else {
            throw fields.invalid("target", "Missing “target” in \(fields.path).", rule: .missingField)
        }
        guard case let .word(word) = raw, let target = SpaceDirection(rawValue: word) else {
            throw fields.invalid("target", "Unknown target in \(fields.path). Use left or right.", rule: .badWindowValue)
        }
        self.target = target
    }

    public func write(to fields: inout ActionFieldWriter) {
        fields.string("target", target.rawValue)
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "target": ["enum": SpaceDirection.allCases.map(\.rawValue),
                       "description": "The Space or desktop to go to: the one to the left or to the right of the current one."],
        ], required: ["target"])
    }

    /// Built-in actions: `space-switch-left` and `space-switch-right`.
    public static func builtIn(_ type: String, value: String?) -> SpaceSwitchAction? {
        value.flatMap(SpaceDirection.init(rawValue:)).map(SpaceSwitchAction.init)
    }

    public static func builtInValues(_ type: String) -> [String?] {
        SpaceDirection.allCases.map(\.rawValue)
    }

    public func iconSource(home: URL) -> IconSource? {
        .symbol(target == .left ? "rectangle.lefthalf.inset.filled.arrow.left" : "rectangle.righthalf.inset.filled.arrow.right")
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(SpaceCommand(direction: target)))
    }
}

/// What Switch Space asks the app to do.
public struct SpaceCommand: ActionStep {
    public let direction: SpaceDirection
}
