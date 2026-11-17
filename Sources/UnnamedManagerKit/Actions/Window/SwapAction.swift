import Foundation

/// Which window Swap Window trades places with (spec v10): a direction,
/// the next or previous one, the first or last one, or one by number.
public enum SwapTarget: Sendable, Hashable {
    /// Focus Window's directions, with the same meaning.
    case window(FocusDirection)
    /// A place in Focus Window's order, from 1.
    case number(Int)
}

/// Swap Window (S-077): the focused window trades place and size with
/// another and keeps focus.
public struct SwapAction: ActionValue {
    public var target: SwapTarget
    public var scope: WindowScope

    public init(_ target: SwapTarget, scope: WindowScope = .all) {
        self.target = target
        self.scope = scope
    }

    public static let kinds = [ActionKind(type: "window.swap", displayName: "Swap Window", symbol: "rectangle.2.swap")]

    public var type: String { "window.swap" }

    public static func blank(_ type: String) -> SwapAction {
        SwapAction(.window(.right))
    }

    /// `target` as the file has it: a number, or a word.
    private enum RawTarget: Decodable {
        case number(Int), word(String)

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Int.self) {
                self = .number(number)
            } else if let word = try? value.decode(String.self) {
                self = .word(word)
            } else {
                throw DecodingError.typeMismatch(Int.self, .init(codingPath: decoder.codingPath,
                                                                 debugDescription: "Expected a direction or a whole number."))
            }
        }
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target", "scope"])
        switch try fields.optional("target") as RawTarget? {
        case nil:
            throw fields.invalid("target", "Missing “target” in \(fields.path).", rule: .missingField)
        case let .word(word):
            guard let direction = FocusDirection(rawValue: word) else {
                let names = FocusDirection.allCases.map(\.rawValue)
                throw fields.invalid("target", "Unknown target “\(word)” in \(fields.path). Use \(names.joined(separator: ", ")), or a number from 1.",
                                     rule: .badWindowValue)
            }
            target = .window(direction)
        case let .number(number):
            guard number >= 1 else {
                throw fields.invalid("target", "“target” in \(fields.path) must be a number from 1.", rule: .badWindowValue)
            }
            target = .number(number)
        }
        scope = try fields.choice("scope") ?? .all
    }

    /// The scope is left out when it's the default, every display.
    public func write(to fields: inout ActionFieldWriter) {
        switch target {
        case let .window(direction): fields.string("target", direction.rawValue)
        case let .number(number): fields.number("target", Double(number))
        }
        if scope != .all { fields.string("scope", scope.rawValue) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "target": ["oneOf": [["enum": FocusDirection.allCases.map(\.rawValue)], ["type": "integer", "minimum": 1]],
                       "description": "The window to swap with: a direction, next, previous, first, last, or its number in Focus Window's order, from 1."],
            "scope": WindowScope.schema,
        ], required: ["target"])
    }

    /// Sideways and up-and-down swaps show their arrows, and a number shows one.
    public func iconSource(home: URL) -> IconSource? {
        let symbol = switch target {
        case .window(.left), .window(.right): "arrow.left.arrow.right.square"
        case .window(.up), .window(.down): "arrow.up.arrow.down.square"
        case .number: "number.square"
        case .window: "rectangle.2.swap"
        }
        return .symbol(symbol)
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(WindowCommand.swap(target, scope: scope)))
    }
}

/// What Swap Window does (S-077).
public enum SwapPick: Equatable, Sendable {
    /// Trade places with this window.
    case window(Int)
    /// The target is the focused window: nothing to do, and no failure.
    case stay
    /// No window there, with what to say.
    case none(String)
}

extension WindowGeometry {
    /// The window Swap Window trades places with (S-077), among `windows`
    /// (Focus Window's candidates, for its scope). `current` is the focused
    /// window's index among them, nil when it isn't one; `frame` is its frame.
    public static func swapPartner(_ target: SwapTarget, current: Int?, frame: CGRect,
                                   windows: [CGRect], owners: [Int32], screens: [Screen]) -> SwapPick {
        let order = cycleOrder(windows, owners: owners, screens: screens)
        func pick(_ index: Int?, else failure: String) -> SwapPick {
            guard let index else { return .none(failure) }
            return index == current ? .stay : .window(index)
        }
        switch target {
        case let .window(direction) where direction == .next || direction == .previous:
            return pick(step(from: current, in: order, direction), else: "No other window to swap with.")
        case .window(.first):
            return pick(order.first, else: "No window to swap with.")
        case .window(.last):
            return pick(order.last, else: "No window to swap with.")
        case let .window(direction):
            let others = windows.indices.filter { $0 != current }
            return pick(neighbor(of: frame, direction, among: others.map { windows[$0] }).map { others[$0] }, else: direction.failure)
        case let .number(number):
            let count = order.count
            return pick(number <= count ? order[number - 1] : nil,
                        else: "No window \(number). There \(count == 1 ? "is" : "are") \(count).")
        }
    }
}
