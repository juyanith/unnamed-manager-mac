import Foundation

/// One `type` an action family handles: its name in the file, its glossary
/// name in the UI, and the SF Symbol the Guide shows for it (S-060).
public struct ActionKind: Sendable, Hashable {
    public let type: String
    public let displayName: String
    /// nil shows no icon, unless the action finds one itself (`iconSource`).
    public let symbol: String?

    public init(type: String, displayName: String, symbol: String? = nil) {
        self.type = type
        self.displayName = displayName
        self.symbol = symbol
    }
}

/// An action family: one module that reads, checks, writes, describes and
/// plans its own kinds of action (S-060). A conforming type is the value
/// stored in the config, so the family and its actions live in one file.
/// Context Aware isn't a family: it combines other actions, and lives in
/// the shell (`Config.Action.contextual`).
public protocol ActionValue: Sendable, Equatable {
    /// The kinds this family handles, in the order the schema lists them.
    static var kinds: [ActionKind] { get }
    /// This action's kind: one of `kinds`.
    var type: String { get }
    /// A blank action of a kind, for the Type picker.
    static func blank(_ type: String) -> Self
    /// Reads one action of a kind. Call `fields.allow` first, so a typo is
    /// reported as an unknown field before anything else.
    init(type: String, fields: ActionFields) throws
    /// The fields after `type`, in the order they're written, defaults left out.
    func write(to fields: inout ActionFieldWriter)
    /// The JSON Schema for a kind's fields, `type` excluded.
    static func schema(_ type: String) -> ActionSchema
    /// What to do in the world. No side effects.
    func plan(home: URL) throws(PlanError) -> ActionPlan
    /// The Guide's icon for this action. Defaults to its kind's symbol.
    func iconSource(home: URL) -> IconSource?
}

extension ActionValue {
    public var kind: ActionKind {
        Self.kinds.first { $0.type == type } ?? ActionKind(type: type, displayName: type)
    }

    public var displayName: String { kind.displayName }

    public func iconSource(home: URL) -> IconSource? {
        kind.symbol.map(IconSource.symbol)
    }

    func isEqual(to other: any ActionValue) -> Bool {
        (other as? Self) == self
    }
}

/// Any family's action, so `Config.Action` can hold it and compare it.
public struct AnyActionValue: Sendable, Equatable {
    public let value: any ActionValue

    public init(_ value: some ActionValue) {
        self.value = value
    }

    public static func == (lhs: AnyActionValue, rhs: AnyActionValue) -> Bool {
        lhs.value.isEqual(to: rhs.value)
    }
}

/// A kind's fields in the JSON Schema: `properties` and the names in `required`.
public struct ActionSchema {
    public var properties: [String: Any]
    public var required: [String]

    public init(_ properties: [String: Any] = [:], required: [String] = []) {
        self.properties = properties
        self.required = required
    }
}

/// The families the app knows. The config reader, the validator, the
/// schema, the writer and the Actions page all read it, so adding a family
/// is one line here (S-060). Tests build their own with `adding`.
public struct ActionRegistry: @unchecked Sendable {
    // Metatypes never change, so sharing them across threads is safe.
    public let families: [any ActionValue.Type]

    public init(families: [any ActionValue.Type]) {
        self.families = families
    }

    public static let standard = ActionRegistry(families: [
        UseApplicationAction.self, OpenAction.self, RunCommandAction.self, SendShortcutAction.self, BasicAction.self,
        MaximizeAction.self, MinimizeAction.self, PlaceAction.self, MoveAction.self, ResizeAction.self, FocusAction.self,
    ])

    public func adding(_ family: any ActionValue.Type) -> ActionRegistry {
        ActionRegistry(families: families + [family])
    }

    /// Every kind, in family order, then each family's own order.
    public var kinds: [ActionKind] {
        families.flatMap { $0.kinds }
    }

    public func family(for type: String) -> (any ActionValue.Type)? {
        families.first { family in family.kinds.contains { $0.type == type } }
    }

    /// Where a JSONDecoder carries a registry other than `standard`.
    public static let userInfoKey = CodingUserInfoKey(rawValue: "net.unnamed.manager.action-registry")!

    /// The decoder's registry, or `standard`.
    static func from(_ decoder: any Decoder) -> ActionRegistry {
        decoder.userInfo[userInfoKey] as? ActionRegistry ?? .standard
    }
}

/// One action's fields as a family reads them, with the same checks and
/// messages for every family.
public struct ActionFields {
    let container: KeyedDecodingContainer<AnyKey>
    /// "an action of type “open”", for messages.
    public let path: String

    init(_ container: KeyedDecodingContainer<AnyKey>, type: String) {
        self.container = container
        path = "an action of type “\(type)”"
    }

    /// Reports the first field that isn't `type` or one of `names`.
    public func allow(_ names: Set<String>) throws {
        try container.rejectUnknown(allowed: names.union(["type"]), at: path)
    }

    public func required<T: Decodable>(_ name: String) throws -> T {
        try container.required(name)
    }

    public func optional<T: Decodable>(_ name: String) throws -> T? {
        try container.decodeIfPresent(T.self, forKey: AnyKey(name))
    }

    public func value<T: Decodable>(_ name: String, default fallback: T) throws -> T {
        try container.value(name, default: fallback)
    }

    /// A field with a value its family doesn't accept, reported under `rule`.
    public func invalid(_ name: String, _ message: String, rule: ConfigRule) -> any Error {
        DecodingError.dataCorrupted(.init(codingPath: container.codingPath + [AnyKey(name)],
                                          debugDescription: message, underlyingError: RuleMarker(rule: rule)))
    }

    /// Decodes a nested action (any family, or Context Aware) with the same registry.
    public func action(_ name: String) throws -> Config.Action? {
        try container.decodeIfPresent(Config.Action.self, forKey: AnyKey(name))
    }
}

/// Writes one action's fields as JSON values on one line, in the order given.
public struct ActionFieldWriter {
    private(set) var fields: [(String, String)] = []

    init() {}

    public mutating func string(_ key: String, _ value: String) {
        fields.append((key, ConfigWriter.quote(value)))
    }

    public mutating func strings(_ key: String, _ values: [String]) {
        fields.append((key, "[" + values.map(ConfigWriter.quote).joined(separator: ", ") + "]"))
    }

    /// An object of strings, keys sorted.
    public mutating func dictionary(_ key: String, _ values: [String: String]) {
        fields.append((key, ConfigWriter.object(values.keys.sorted().map { ($0, ConfigWriter.quote(values[$0]!)) })))
    }

    public mutating func number(_ key: String, _ value: Double) {
        fields.append((key, value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)))
    }

    public mutating func bool(_ key: String, _ value: Bool) {
        fields.append((key, value ? "true" : "false"))
    }

    /// An object of numbers, in the order given.
    public mutating func numbers(_ key: String, _ values: [(String, Double)]) {
        var inner = ActionFieldWriter()
        for (name, value) in values { inner.number(name, value) }
        fields.append((key, ConfigWriter.object(inner.fields)))
    }

    /// An array of numbers.
    public mutating func numberList(_ key: String, _ values: [Double]) {
        var inner = ActionFieldWriter()
        for value in values { inner.number("", value) }
        fields.append((key, "[" + inner.fields.map(\.1).joined(separator: ", ") + "]"))
    }
}

/// A step a family plans that the built-in `ActionPlan` cases don't cover.
/// The app carries it out by conforming the type to its own performer
/// protocol, so a new family changes no shared file.
public protocol ActionStep: Sendable, Equatable {}

public struct AnyActionStep: Sendable, Equatable {
    public let step: any ActionStep

    public init(_ step: some ActionStep) {
        self.step = step
    }

    public static func == (lhs: AnyActionStep, rhs: AnyActionStep) -> Bool {
        func equal<S: ActionStep>(_ step: S) -> Bool { (rhs.step as? S) == step }
        return equal(lhs.step)
    }
}
