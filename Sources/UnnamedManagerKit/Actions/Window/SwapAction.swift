import Foundation

/// Swap Window (S-077): the focused window trades place and size with
/// another and keeps focus.
public struct SwapAction: ActionValue {
    public var target: WindowTarget
    public var scope: WindowScope

    public init(_ target: WindowTarget, scope: WindowScope = .all) {
        self.target = target
        self.scope = scope
    }

    public static let kinds = [ActionKind(type: "window.swap", displayName: "Swap Window", symbol: "rectangle.2.swap")]

    public var type: String { "window.swap" }

    public static func blank(_ type: String) -> SwapAction {
        SwapAction(.window(.right))
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target", "scope"])
        guard let target = try fields.target("target") else {
            throw fields.invalid("target", "Missing “target” in \(fields.path).", rule: .missingField)
        }
        self.target = target
        scope = try fields.choice("scope") ?? .all
    }

    /// The scope is left out when it's the default, every display.
    public func write(to fields: inout ActionFieldWriter) {
        fields.target("target", target)
        if scope != .all { fields.string("scope", scope.rawValue) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "target": WindowTarget.schema("The window to swap with: a direction, next, previous, first, last, or its number in Focus Window's order, from 1."),
            "scope": WindowScope.schema,
        ], required: ["target"])
    }

    /// Built-in actions (spec v11): `window-swap-left`, `window-swap-3` and the others.
    public static func builtIn(_ type: String, value: String?) -> SwapAction? {
        value.flatMap(WindowTarget.init(builtIn:)).map { SwapAction($0) }
    }

    public static func builtInValues(_ type: String) -> [String?] {
        WindowTarget.builtInValues
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
    /// (Focus Window's candidates, for its scope, front to back). `current`
    /// is the focused window's index among them, nil when it isn't one;
    /// `frame` is its frame.
    public static func swapPartner(_ target: WindowTarget, current: Int?, frame: CGRect, windows: [SeenWindow],
                                   screens: [Screen], settings: Config.Windows = Config.Windows()) -> SwapPick {
        let order = cycleOrder(windows, screens: screens, settings: settings)
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
            return pick(neighbor(of: frame, direction, among: others.map { windows[$0] }, settings: settings).map { others[$0] },
                        else: direction.failure)
        case let .number(number):
            let count = order.count
            return pick(number <= count ? order[number - 1] : nil, else: WindowTarget.pastTheEnd(number, count: count))
        }
    }
}
