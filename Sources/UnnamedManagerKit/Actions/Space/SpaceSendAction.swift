import Foundation

/// Where Send to Space puts the window (spec v20): the Space beside its
/// own, or a desktop by number, counting desktops only.
public enum SpaceTarget: Sendable, Hashable {
    case side(SpaceDirection)
    case number(Int)

    /// The target in a built-in name, such as "left" or "2".
    init?(builtIn value: String) {
        if let number = BuiltInAction.number(value) {
            self = .number(number)
        } else if let direction = SpaceDirection(rawValue: value) {
            self = .side(direction)
        } else {
            return nil
        }
    }

    /// Reads `target`, which is required: left, right or a number from 1.
    /// Any other value, the string "2" included, is `bad-window-value`.
    init(_ fields: ActionFields) throws {
        enum Raw: Decodable {
            case number(Int), word(String), other

            init(from decoder: any Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let number = try? value.decode(Int.self) {
                    self = .number(number)
                } else if let word = try? value.decode(String.self) {
                    self = .word(word)
                } else if (try? value.decode(Double.self)) != nil {
                    self = .other
                } else {
                    throw DecodingError.typeMismatch(Int.self, .init(codingPath: decoder.codingPath,
                                                                     debugDescription: "Expected left, right or a whole number."))
                }
            }
        }
        switch try fields.optional("target") as Raw? {
        case nil:
            throw fields.invalid("target", "Missing “target” in \(fields.path).", rule: .missingField)
        case let .word(word):
            guard let direction = SpaceDirection(rawValue: word) else {
                throw fields.invalid("target", "Unknown target “\(word)” in \(fields.path). Use left, right, or a number from 1.",
                                     rule: .badWindowValue)
            }
            self = .side(direction)
        case let .number(number) where number >= 1:
            self = .number(number)
        case .number, .other:
            throw fields.invalid("target", "“target” in \(fields.path) must be left, right, or a number from 1.", rule: .badWindowValue)
        }
    }

    func write(to fields: inout ActionFieldWriter) {
        switch self {
        case let .side(direction): fields.string("target", direction.rawValue)
        case let .number(number): fields.number("target", Double(number))
        }
    }

    static func schema(_ description: String) -> [String: Any] {
        ["oneOf": [["enum": SpaceDirection.allCases.map(\.rawValue)], ["type": "integer", "minimum": 1]],
         "description": description]
    }
}

/// Send to Space (S-096, spec v20): puts the focused window on another
/// Space, and with `follow` goes there with it.
public struct SpaceSendAction: ActionValue {
    public var target: SpaceTarget
    public var follow: Bool

    public init(_ target: SpaceTarget, follow: Bool = false) {
        self.target = target
        self.follow = follow
    }

    public static let kinds = [ActionKind(type: "space.send", displayName: "Send to Space", symbol: "macwindow.badge.plus")]

    public var type: String { "space.send" }

    public static func blank(_ type: String) -> SpaceSendAction {
        SpaceSendAction(.number(2))
    }

    /// `target` is required: left, right or a number from 1. Any other
    /// value, the string "2" included, is `bad-window-value`.
    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target", "follow"])
        target = try SpaceTarget(fields)
        follow = try fields.value("follow", default: false)
    }

    /// `follow` is left out when it's off, the default.
    public func write(to fields: inout ActionFieldWriter) {
        target.write(to: &fields)
        if follow { fields.bool("follow", true) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "target": SpaceTarget.schema(
                "Where the window goes: the Space or desktop to the left or right of its own, or the one with that number, from 1."),
            "follow": ["type": "boolean",
                       "description": "Go to that Space or desktop with the window. Default false: stay where you are."],
        ], required: ["target"])
    }

    /// Built-in actions: `space-send-left`, `space-send-right` and
    /// `space-send-2` and the other numbers, all with `follow` off.
    public static func builtIn(_ type: String, value: String?) -> SpaceSendAction? {
        value.flatMap(SpaceTarget.init(builtIn:)).map { SpaceSendAction($0) }
    }

    public static func builtInValues(_ type: String) -> [String?] {
        SpaceDirection.allCases.map(\.rawValue)
    }

    public func iconSource(home: URL) -> IconSource? {
        switch target {
        case .side(.left): .symbol("arrow.left.square")
        case .side(.right): .symbol("arrow.right.square")
        case let .number(number) where number <= 50: .symbol("\(number).square")
        case .number: .symbol("number.square")
        }
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(SpaceSendCommand(target: target, follow: follow)))
    }
}

/// What Send to Space asks the app to do.
public struct SpaceSendCommand: ActionStep {
    public let target: SpaceTarget
    public let follow: Bool
}

/// Where a window is among its display's desktops (spec v20).
public enum DesktopPlace: Equatable, Sendable {
    /// On desktop `number` of `count`, from 1, left to right, full-screen Spaces not counted.
    case desktop(Int, of: Int)
    /// In a full-screen Space, which Send to Space can't move.
    case fullScreen
    /// Set to show on every Space.
    case everySpace
    /// The platform didn't say.
    case unknown
}

/// What Send to Space does.
public enum SpaceSendPick: Equatable, Sendable {
    /// Put the window on this desktop, from 1.
    case desktop(Int)
    /// Already there, or at the end for left or right: nothing, and no failure.
    case stay
    /// Not possible, with what to say. Plays the alert sound.
    case none(String)
}

public enum SpaceSend {
    /// Where the window goes from `place` (spec v20). Left and right
    /// don't wrap; a number past the last desktop fails.
    public static func pick(_ target: SpaceTarget, from place: DesktopPlace, appName: String) -> SpaceSendPick {
        let (current, count): (Int, Int)
        switch place {
        case let .desktop(number, of: total): (current, count) = (number, total)
        case .fullScreen: return .none("\(appName)'s window is full screen, so it can't go to another Space.")
        case .everySpace: return .none("\(appName)'s window is on every Space.")
        case .unknown: return .none("Unable to find the Space of \(appName)'s window.")
        }
        switch target {
        case .side(.left):
            return current > 1 ? .desktop(current - 1) : .stay
        case .side(.right):
            return current < count ? .desktop(current + 1) : .stay
        case let .number(number) where number > count:
            return .none("No Space \(number). There \(count == 1 ? "is" : "are") \(count).")
        case let .number(number):
            return number == current ? .stay : .desktop(number)
        }
    }
}
