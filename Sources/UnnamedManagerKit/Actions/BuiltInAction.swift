import Foundation

/// Built-in actions (S-079, spec v11): actions a binding names without
/// defining them, such as `window-place-left-half`. A name is the kind's
/// type with hyphens for its dots, then a hyphen and one value of the
/// kind's main field in lowercase words joined by hyphens. Each family
/// says which of its values have one (`ActionValue.builtIn`).
public enum BuiltInAction {
    /// One built-in action, for the Action picker.
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let action: Config.Action
    }

    /// "window.place" → "window-place".
    public static func prefix(_ type: String) -> String {
        type.replacingOccurrences(of: ".", with: "-")
    }

    /// "leftTwoThirds" → "left-two-thirds". Numbers stay as they are.
    public static func words(_ value: String) -> String {
        value.reduce(into: "") { result, char in
            if char.isUppercase { result += "-" + char.lowercased() } else { result.append(char) }
        }
    }

    /// "left-two-thirds" → "leftTwoThirds", the way the file writes the value.
    static func value(_ words: String) -> String {
        let parts = words.split(separator: "-", omittingEmptySubsequences: false)
        return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }
            .joined()
    }

    /// A number in a built-in name: digits, from 1, with no leading zero.
    static func number(_ text: String) -> Int? {
        guard let first = text.first, first != "0", text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) else { return nil }
        return Int(text)
    }

    /// The action a built-in name stands for, or nil when it isn't one.
    /// Names are case-sensitive, and the value must be written in words:
    /// `window-place-leftHalf` isn't a built-in name.
    public static func action(named name: String, registry: ActionRegistry = .standard) -> Config.Action? {
        for kind in registry.kinds where kind.replacedBy == nil {
            guard let family = registry.family(for: kind.type) else { continue }
            let prefix = prefix(kind.type)
            let found: (any ActionValue)?
            if name == prefix {
                found = family.builtIn(kind.type, value: nil)
            } else if name.hasPrefix(prefix + "-") {
                let rest = String(name.dropFirst(prefix.count + 1))
                let value = value(rest)
                found = words(value) == rest ? family.builtIn(kind.type, value: value) : nil
            } else {
                continue
            }
            if let found { return .family(AnyActionValue(found)) }
        }
        return nil
    }

    /// Every built-in action with a listed value, kind by kind, in the
    /// registry's order. Numbers with no upper limit aren't listed.
    public static func entries(registry: ActionRegistry = .standard) -> [Entry] {
        registry.kinds.filter { $0.replacedBy == nil }.flatMap { kind -> [Entry] in
            guard let family = registry.family(for: kind.type) else { return [] }
            return family.builtInValues(kind.type).compactMap { value in
                guard let action = family.builtIn(kind.type, value: value) else { return nil }
                let name = value.map { prefix(kind.type) + "-" + words($0) } ?? prefix(kind.type)
                return Entry(name: name, action: .family(AnyActionValue(action)))
            }
        }
    }
}

extension Config {
    /// The action a binding names (spec v11): the one in `actions`, which
    /// overrides a built-in action of the same name, or else the built-in one.
    public func action(named id: String) -> Action? {
        actions[id] ?? BuiltInAction.action(named: id)
    }

    /// Whether an action in `actions` has a built-in action's name, so it overrides it.
    public static func overridesBuiltIn(_ id: String) -> Bool {
        BuiltInAction.action(named: id) != nil
    }
}
