import Foundation

/// A key, named by its physical position on the US ANSI layout (SPEC.md,
/// Key names). Names are case-insensitive; `name` is the canonical spelling.
public enum KeyName: String, CaseIterable, Sendable, Hashable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case d0 = "0", d1 = "1", d2 = "2", d3 = "3", d4 = "4", d5 = "5", d6 = "6", d7 = "7", d8 = "8", d9 = "9"
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24
    case space, tab, enter, backspace, delete, escape
    case left, right, up, down, home, end, pageup, pagedown
    case grave, minus, equal, leftbracket, rightbracket, backslash
    case semicolon, quote, comma, period, slash

    /// Parses a key name in any capitalization: "space", "SPACE", "Space".
    public init?(parsing text: String) {
        self.init(rawValue: text.lowercased())
    }

    /// The canonical spelling used in the config file and the Guide.
    public var name: String {
        switch self {
        case .pageup: "PageUp"
        case .pagedown: "PageDown"
        case .leftbracket: "LeftBracket"
        case .rightbracket: "RightBracket"
        default:
            rawValue.count == 1 ? rawValue.uppercased() : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// The macOS virtual key code (Carbon kVK_*), or nil for keys a Mac
    /// keyboard doesn't have (F21 to F24).
    public var keyCode: UInt16? { Self.codes[self] }

    /// The key at a virtual key code, or nil for keys with no name here.
    public init?(keyCode: UInt16) {
        guard let key = Self.byCode[keyCode] else { return nil }
        self = key
    }

    private static let codes: [KeyName: UInt16] = [
        .a: 0x00, .s: 0x01, .d: 0x02, .f: 0x03, .h: 0x04, .g: 0x05, .z: 0x06, .x: 0x07,
        .c: 0x08, .v: 0x09, .b: 0x0B, .q: 0x0C, .w: 0x0D, .e: 0x0E, .r: 0x0F, .y: 0x10,
        .t: 0x11, .d1: 0x12, .d2: 0x13, .d3: 0x14, .d4: 0x15, .d6: 0x16, .d5: 0x17,
        .equal: 0x18, .d9: 0x19, .d7: 0x1A, .minus: 0x1B, .d8: 0x1C, .d0: 0x1D,
        .rightbracket: 0x1E, .o: 0x1F, .u: 0x20, .leftbracket: 0x21, .i: 0x22, .p: 0x23,
        .enter: 0x24, .l: 0x25, .j: 0x26, .quote: 0x27, .k: 0x28, .semicolon: 0x29,
        .backslash: 0x2A, .comma: 0x2B, .slash: 0x2C, .n: 0x2D, .m: 0x2E, .period: 0x2F,
        .tab: 0x30, .space: 0x31, .grave: 0x32, .backspace: 0x33, .escape: 0x35,
        .f17: 0x40, .f18: 0x4F, .f19: 0x50, .f20: 0x5A, .f5: 0x60, .f6: 0x61, .f7: 0x62,
        .f3: 0x63, .f8: 0x64, .f9: 0x65, .f11: 0x67, .f13: 0x69, .f16: 0x6A, .f14: 0x6B,
        .f10: 0x6D, .f12: 0x6F, .f15: 0x71, .home: 0x73, .pageup: 0x74, .delete: 0x75,
        .f4: 0x76, .end: 0x77, .f2: 0x78, .pagedown: 0x79, .f1: 0x7A,
        .left: 0x7B, .right: 0x7C, .down: 0x7D, .up: 0x7E,
    ]
    private static let byCode: [UInt16: KeyName] = Dictionary(uniqueKeysWithValues: codes.map { ($1, $0) })
}

/// The four modifiers a chord can use. `Primary` is ⌘ on the Mac. Three
/// names stand for groups: `Hyper` is all four, `Meh` is ⌃⌥⇧ and `CAG` is
/// ⌃⌥⌘ (SPEC.md, Key syntax).
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let hyper: Modifiers = [.control, .option, .shift, .command]
    public static let meh: Modifiers = [.control, .option, .shift]
    public static let cag: Modifiers = [.control, .option, .command]

    /// The Mac's own modifier symbols.
    public static let symbols: [Character: Modifiers] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]

    /// Parses one modifier name, case-insensitive ("Ctrl", "Opt", "Command"),
    /// or a run of symbols such as "⌃⌥".
    public init?(parsing text: String) {
        switch text.lowercased() {
        case "ctrl", "control": self = .control
        case "alt", "opt", "option": self = .option
        case "shift": self = .shift
        case "cmd", "command", "primary": self = .command
        case "hyper": self = .hyper
        case "meh": self = .meh
        case "cag": self = .cag
        default:
            guard let modifiers = Self(symbols: text) else { return nil }
            self = modifiers
        }
    }

    /// Parses one or more symbols: "⌘", "⌃⌥⇧". Nil for anything else.
    public init?(symbols text: some StringProtocol) {
        guard !text.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for char in text {
            guard let modifier = Self.symbols[char] else { return nil }
            modifiers.formUnion(modifier)
        }
        self = modifiers
    }

    /// Canonical names: "Hyper", "Meh" or "CAG" when the set is exactly that
    /// group, else Ctrl, Alt, Shift, Cmd in that order.
    public var names: [String] {
        if self == .hyper { return ["Hyper"] }
        if self == .meh { return ["Meh"] }
        if self == .cag { return ["CAG"] }
        var out: [String] = []
        if contains(.control) { out.append("Ctrl") }
        if contains(.option) { out.append("Alt") }
        if contains(.shift) { out.append("Shift") }
        if contains(.command) { out.append("Cmd") }
        return out
    }
}

/// Zero or more modifiers and one key: "Hyper+Space", "Ctrl+Alt+L", "E".
public struct Chord: Sendable, Hashable, CustomStringConvertible {
    public var modifiers: Modifiers
    public var key: KeyName

    public init(modifiers: Modifiers = [], key: KeyName) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Hyper+Comma, Hyper+Period and Hyper+Slash start macOS's diagnostics
    /// (sysdiagnose), which take them before any event tap sees them.
    public var isKeptByMacOS: Bool {
        modifiers == .hyper && [.comma, .period, .slash].contains(key)
    }

    /// Parses a chord token: "Hyper+Space", "Ctrl+Opt+L", "⌃⌥⇧T" or
    /// "⌘+F". Returns nil when a part isn't a known name.
    public init?(parsing token: String) {
        let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last else { return nil }
        // Symbols can sit right before the key, as macOS writes shortcuts.
        let symbols = last.prefix { Modifiers.symbols[$0] != nil }
        guard let key = KeyName(parsing: String(last.dropFirst(symbols.count))) else { return nil }
        var modifiers = Modifiers(symbols: symbols) ?? []
        for part in parts.dropLast() {
            guard let modifier = Modifiers(parsing: part) else { return nil }
            modifiers.formUnion(modifier)
        }
        self.init(modifiers: modifiers, key: key)
    }

    /// Canonical form, such as "Hyper+Space".
    public var description: String {
        (modifiers.names + [key.name]).joined(separator: "+")
    }
}

/// An entry's full key path: the leader chord, then zero or more step keys.
public struct KeySequence: Sendable, Hashable, CustomStringConvertible {
    public var leader: Chord
    public var steps: [Chord]

    public init(leader: Chord, steps: [Chord] = []) {
        self.leader = leader
        self.steps = steps
    }

    /// Parses "Hyper+Space A T". Returns nil when any token fails to parse.
    public init?(parsing text: String) {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let leader = Chord(parsing: first) else { return nil }
        var steps: [Chord] = []
        for token in tokens.dropFirst() {
            guard let step = Chord(parsing: token) else { return nil }
            steps.append(step)
        }
        self.init(leader: leader, steps: steps)
    }

    public var isLeader: Bool { steps.isEmpty }

    /// The path one level up, or nil for a leader.
    public var parent: KeySequence? {
        isLeader ? nil : KeySequence(leader: leader, steps: Array(steps.dropLast()))
    }

    /// The key that selects this entry inside its parent menu, or nil for a leader.
    public var lastStep: Chord? { steps.last }

    /// Canonical form, such as "Hyper+Space A T".
    public var description: String {
        ([leader] + steps).map(\.description).joined(separator: " ")
    }
}
