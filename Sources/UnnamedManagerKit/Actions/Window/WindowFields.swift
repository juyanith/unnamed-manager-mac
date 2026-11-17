import Foundation

/// The field checks the window families share (spec v2, Window actions).
extension ActionFields {
    /// Which one of `names` the action has. Two of them is
    /// `conflicting-fields`, none is `missing-field`.
    func one(of names: [String]) throws -> String {
        let present = names.filter { container.contains(AnyKey($0)) }
        if present.count > 1 {
            throw invalid(present[1], "Use only one of “\(present[0])” and “\(present[1])” in \(path).", rule: .conflictingFields)
        }
        guard let name = present.first else {
            let list = names.map { "“\($0)”" }
            throw invalid(names[0], "Add \(list.dropLast().joined(separator: ", ")) or \(list.last!) to \(path).", rule: .missingField)
        }
        return name
    }

    /// Whether the action has a field, for fields that only go with another.
    func has(_ name: String) -> Bool {
        container.contains(AnyKey(name))
    }

    /// A field that doesn't go with `other`.
    func conflict(_ name: String, with other: String) -> any Error {
        invalid(name, "“\(name)” doesn't go with “\(other)” in \(path).", rule: .conflictingFields)
    }

    /// One of a window field's values, such as a preset or a direction.
    func choice<Value: RawRepresentable & CaseIterable>(_ name: String) throws -> Value? where Value.RawValue == String {
        guard let raw: String = try optional(name) else { return nil }
        guard let value = Value(rawValue: raw) else {
            let names = Value.allCases.map(\.rawValue)
            throw invalid(name, "Unknown \(name) “\(raw)” in \(path). Use \(names.dropLast().joined(separator: ", ")) or \(names.last!).",
                          rule: .badWindowValue)
        }
        return value
    }

    /// Focus Window's and Swap Window's target: a word, or a number from 1
    /// (spec v10, v11). Neither a string nor a whole number is `wrong-type`.
    func target(_ name: String) throws -> WindowTarget? {
        enum Raw: Decodable {
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
        switch try optional(name) as Raw? {
        case nil:
            return nil
        case let .word(word):
            guard let direction = FocusDirection(rawValue: word) else {
                let names = FocusDirection.allCases.map(\.rawValue)
                throw invalid(name, "Unknown \(name) “\(word)” in \(path). Use \(names.joined(separator: ", ")), or a number from 1.",
                              rule: .badWindowValue)
            }
            return .window(direction)
        case let .number(number):
            guard number >= 1 else {
                throw invalid(name, "“\(name)” in \(path) must be a number from 1.", rule: .badWindowValue)
            }
            return .number(number)
        }
    }

    /// An object of numbers, as strict as an action: unknown keys and
    /// missing required ones are reported.
    func numbers(_ name: String, required: [String], others: [String] = []) throws -> [String: Double]? {
        guard let object: [String: Double] = try optional(name) else { return nil }
        let where_ = "“\(name)” in \(path)"
        if let extra = object.keys.sorted().first(where: { !required.contains($0) && !others.contains($0) }) {
            throw UnknownFieldError(field: extra, path: where_)
        }
        if let missing = required.first(where: { object[$0] == nil }) {
            throw invalid(name, "Missing “\(missing)” in \(where_).", rule: .missingField)
        }
        return object
    }

    /// A fraction of the usable area out of its range.
    func badFraction(_ name: String, _ message: String) -> any Error {
        invalid(name, "\(message) in “\(name)” in \(path).", rule: .badFraction)
    }
}

extension ActionFieldWriter {
    /// A target as the file writes it: a word, or a number.
    mutating func target(_ key: String, _ target: WindowTarget) {
        switch target {
        case let .window(direction): string(key, direction.rawValue)
        case let .number(number): self.number(key, Double(number))
        }
    }
}

/// JSON Schema pieces for fractions and points.
enum WindowSchema {
    static var fraction: [String: Any] { ["type": "number", "minimum": 0, "maximum": 1] }
    static var size: [String: Any] { ["type": "number", "exclusiveMinimum": 0, "maximum": 1] }
    static var points: [String: Any] { ["type": "number"] }

    static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": required, "properties": properties]
    }
}
