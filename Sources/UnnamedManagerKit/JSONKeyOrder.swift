import Foundation

/// Reads the order of keys in one top-level JSON object, which `Codable`
/// loses. Used to keep the `actions` object in the order it was written
/// (S-033). Returns [] for anything it can't read; the caller then sorts.
public enum JSONKeyOrder {
    public static func keys(ofTopLevelObject name: String, in data: Data) -> [String] {
        var scanner = Scanner(bytes: Array(data))
        guard scanner.expect(UInt8(ascii: "{")) else { return [] }
        while let key = scanner.objectKey() {
            if key == name {
                return scanner.peek() == UInt8(ascii: "{") ? scanner.keysOfObject() : []
            }
            guard scanner.skipValue() else { return [] }
            scanner.skipComma()
        }
        return []
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func peek() -> UInt8? {
            skipWhitespace()
            return index < bytes.count ? bytes[index] : nil
        }

        mutating func expect(_ byte: UInt8) -> Bool {
            guard peek() == byte else { return false }
            index += 1
            return true
        }

        mutating func skipComma() { _ = expect(UInt8(ascii: ",")) }

        /// The next `"key":` in an object, or nil at the closing brace.
        mutating func objectKey() -> String? {
            guard peek() == UInt8(ascii: "\""), let key = string(), expect(UInt8(ascii: ":")) else { return nil }
            return key
        }

        /// The keys of the object at the current position, in order.
        mutating func keysOfObject() -> [String] {
            guard expect(UInt8(ascii: "{")) else { return [] }
            var keys: [String] = []
            while let key = objectKey() {
                keys.append(key)
                guard skipValue() else { return keys }
                skipComma()
            }
            return keys
        }

        /// A JSON string, decoded with escapes.
        mutating func string() -> String? {
            guard expect(UInt8(ascii: "\"")) else { return nil }
            let start = index - 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""):
                    index += 1
                    return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                default: index += 1
                }
            }
            return nil
        }

        /// Skips one value of any kind. False when the text ends early.
        mutating func skipValue() -> Bool {
            guard let first = peek() else { return false }
            switch first {
            case UInt8(ascii: "\""):
                return string() != nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while index < bytes.count {
                    switch bytes[index] {
                    case UInt8(ascii: "\""):
                        guard string() != nil else { return false }
                        continue
                    case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                    case UInt8(ascii: "}"), UInt8(ascii: "]"):
                        depth -= 1
                        if depth == 0 { index += 1; return true }
                    default: break
                    }
                    index += 1
                }
                return false
            default:
                // A number, true, false or null.
                while index < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) {
                    index += 1
                }
                return true
            }
        }
    }
}
