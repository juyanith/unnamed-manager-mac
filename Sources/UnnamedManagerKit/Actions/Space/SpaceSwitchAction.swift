import Foundation

/// Which way Switch Space goes (spec v17).
public enum SpaceDirection: String, CaseIterable, Sendable {
    case left, right

    public var displayName: String { rawValue.capitalized }
}

/// Switch Space (S-088, spec v17): go to the Space to the left or right on
/// the focused window's display, without the slide, or to a desktop by
/// number (S-097, spec v22). Not a window action: with no focused window,
/// left and right do nothing, and that isn't a failure.
public struct SpaceSwitchAction: ActionValue {
    public var target: SpaceTarget

    public init(_ target: SpaceTarget) {
        self.target = target
    }

    public init(_ direction: SpaceDirection) {
        self.init(.side(direction))
    }

    public static let kinds = [ActionKind(type: "space.switch", displayName: "Switch Space", symbol: "rectangle.3.group")]

    public var type: String { "space.switch" }

    public static func blank(_ type: String) -> SpaceSwitchAction {
        SpaceSwitchAction(.right)
    }

    /// `target` is required: left, right or a number from 1 (spec v22). Any
    /// other value, the string "2" included, is `bad-window-value`.
    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target"])
        target = try SpaceTarget(fields)
    }

    public func write(to fields: inout ActionFieldWriter) {
        target.write(to: &fields)
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "target": SpaceTarget.schema(
                "The Space or desktop to go to: the one to the left or to the right of the current one, or the one with that number, from 1."),
        ], required: ["target"])
    }

    /// Built-in actions: `space-switch-left`, `space-switch-right`, and
    /// `space-switch-1` and the other numbers (spec v22).
    public static func builtIn(_ type: String, value: String?) -> SpaceSwitchAction? {
        value.flatMap(SpaceTarget.init(builtIn:)).map(SpaceSwitchAction.init)
    }

    public static func builtInValues(_ type: String) -> [String?] {
        SpaceDirection.allCases.map(\.rawValue)
    }

    public func iconSource(home: URL) -> IconSource? {
        switch target {
        case .side(.left): .symbol("rectangle.lefthalf.inset.filled.arrow.left")
        case .side(.right): .symbol("rectangle.righthalf.inset.filled.arrow.right")
        case let .number(number) where number <= 50: .symbol("\(number).circle")
        case .number: .symbol("number.circle")
        }
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .custom(AnyActionStep(SpaceCommand(target: target)))
    }
}

/// What Switch Space asks the app to do.
public struct SpaceCommand: ActionStep {
    public let target: SpaceTarget

    public init(target: SpaceTarget) {
        self.target = target
    }
}

/// A display's Spaces, in Mission Control's order, and the one on screen.
public struct SpaceStrip: Equatable, Sendable {
    /// For each Space, left to right: true for a desktop, false for a full-screen app.
    public var desktops: [Bool]
    /// The index in `desktops` of the Space on screen.
    public var current: Int

    public init(desktops: [Bool], current: Int) {
        self.desktops = desktops
        self.current = current
    }
}

/// What Switch Space by number does (spec v22).
public enum SpaceSwitchPick: Equatable, Sendable {
    /// Swipe this many Spaces this way, full-screen ones included.
    case swipe(SpaceDirection, count: Int)
    /// Already there: nothing, and no failure.
    case stay
    /// Not possible, with what to say. Plays the alert sound.
    case none(String)
}

public enum SpaceSwitch {
    /// How to reach desktop `number` from the Space on screen. Numbers
    /// count desktops only, but a swipe passes full-screen Spaces too, so
    /// the count is of every Space between.
    public static func pick(_ number: Int, in strip: SpaceStrip) -> SpaceSwitchPick {
        let desktops = strip.desktops.indices.filter { strip.desktops[$0] }
        guard number <= desktops.count else {
            return .none("No Space \(number). There \(desktops.count == 1 ? "is" : "are") \(desktops.count).")
        }
        let distance = desktops[number - 1] - strip.current
        if distance == 0 { return .stay }
        return .swipe(distance > 0 ? .right : .left, count: abs(distance))
    }
}
