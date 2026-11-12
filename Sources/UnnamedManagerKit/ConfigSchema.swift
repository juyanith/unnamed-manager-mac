import Foundation

/// The JSON Schema for config.json (S-039), so editors validate and
/// autocomplete the file. It's built from the same key names, modifiers and
/// action types the app uses, so it can't drift from the code. The app
/// writes it next to the config as config.schema.json.
public enum ConfigSchema {
    public static let fileName = "config.schema.json"

    /// Modifier names a chord may use.
    public static let modifierNames = ["Control", "Ctrl", "Option", "Opt", "Alt", "Shift", "Command", "Cmd",
                                       "Primary", "Hyper", "Meh", "CAG"]

    /// One chord, any capitalization: modifier names or symbols joined by +,
    /// then a key, which symbols may come right before ("⌃⌥⇧T").
    public static var chordPattern: String {
        let modifiers = modifierNames.map(anyCase).joined(separator: "|")
        let symbols = "[" + String(Modifiers.symbols.keys.sorted()) + "]"
        let keys = KeyName.allCases.map(\.name).sorted { $0.count > $1.count }.map(anyCase).joined(separator: "|")
        return "(?:(?:\(modifiers)|\(symbols)+)\\+)*\(symbols)*(?:\(keys))"
    }

    /// A key path: a chord, then step keys, separated by spaces.
    public static var keysPattern: String {
        "^\\s*\(chordPattern)(?:\\s+\(chordPattern))*\\s*$"
    }

    /// "Cmd" → "[Cc][Mm][Dd]", since JSON Schema patterns have no ignore-case flag.
    static func anyCase(_ word: String) -> String {
        word.map { char in
            let lower = char.lowercased(), upper = char.uppercased()
            return lower == upper ? NSRegularExpression.escapedPattern(for: String(char)) : "[\(upper)\(lower)]"
        }.joined()
    }

    public static var json: String {
        json(registry: .standard)
    }

    /// The schema for the families in `registry` (S-060).
    public static func json(registry: ActionRegistry) -> String {
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "Unnamed Manager config",
            "type": "object",
            "required": ["version", "entries"],
            "additionalProperties": false,
            "properties": [
                "$schema": ["type": "string"],
                "version": ["const": Config.supportedVersion],
                "runtime": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "cancelKey": ["type": "string", "description": "Ends a sequence. Default Escape."],
                        "backKey": ["type": "string", "description": "Goes up one menu. \"\" turns Back off. Default Backspace."],
                        "showHud": ["type": "boolean", "description": "Show the Guide. Default true."],
                        "hudDelayMs": ["type": "integer", "minimum": 0, "description": "Idle time before the Guide shows."],
                        "timeoutMs": ["type": "integer", "minimum": 0, "description": "Idle time with the Guide up before the sequence ends. 0 is off."],
                    ],
                ],
                "ui": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "theme": ["enum": ["system", "light", "dark"]],
                        "position": ["enum": ["center", "top", "bottom"]],
                        "errorFlash": ["type": "boolean"],
                        "errorBell": ["type": "boolean"],
                    ],
                ],
                "entries": [
                    "type": "array",
                    "items": [
                        "type": "object", "additionalProperties": false, "required": ["keys", "title"],
                        "properties": [
                            "keys": ["type": "string", "pattern": keysPattern,
                                     "description": "The leader chord, then step keys: \"Hyper+Space A T\". Modifiers: Ctrl, Alt or Opt, Shift, Cmd, Primary, Hyper (all four), Meh (Ctrl+Alt+Shift), CAG (Ctrl+Alt+Cmd), or the symbols ⌃⌥⇧⌘ (\"⌃⌥⇧T\"). A single chord with an action is a direct binding."],
                            "title": ["type": "string", "minLength": 1],
                            "action": ["type": "string", "description": "An id in actions. Without one, the entry is a menu."],
                            "icon": ["type": "string", "minLength": 1,
                                     "description": "Its icon in the Guide: an SF Symbol name such as \"terminal\", or a path starting with / or ~ for that file's icon. Without one, apps and Open targets show their own icon."],
                        ],
                    ],
                ],
                "actions": ["type": "object", "additionalProperties": ["$ref": "#/$defs/action"]],
                "contexts": [
                    "type": "array",
                    "items": [
                        "type": "object", "additionalProperties": false, "required": ["id", "apps"],
                        "properties": [
                            "id": ["type": "string", "minLength": 1],
                            "apps": ["type": "array", "items": ["type": "string"], "description": "Bundle ids."],
                        ],
                    ],
                ],
            ],
            "$defs": [
                "action": ["oneOf": actionVariants(allowingContextual: true, registry: registry)],
                "plainAction": ["oneOf": actionVariants(allowingContextual: false, registry: registry)],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func actionVariants(allowingContextual: Bool, registry: ActionRegistry) -> [[String: Any]] {
        // The type is a one-item enum, not a const: editors that read the
        // schema as an older draft ignore const, and then Do Nothing and
        // Show Help, which have no other fields, both match and oneOf fails.
        func variant(_ type: String, _ fields: [String: Any], required: [String] = []) -> [String: Any] {
            [
                "type": "object", "additionalProperties": false, "required": ["type"] + required,
                "properties": fields.merging(["type": ["enum": [type]]]) { a, _ in a },
            ]
        }
        var variants = [
            variant("application", [
                "bundleId": ["type": "string"],
                "mode": ["enum": Config.AppMode.allCases.map(\.rawValue),
                         "description": "focusOrStart (default): bring it forward, starting it if needed. focus: only if running. start: a new copy."],
            ], required: ["bundleId"]),
            variant("open", ["target": ["type": "string"]], required: ["target"]),
            variant("exec", [
                "command": ["type": "array", "items": ["type": "string"], "minItems": 1],
                "cwd": ["type": "string"],
                "env": ["type": "object", "additionalProperties": ["type": "string"]],
            ], required: ["command"]),
            variant("send", ["keys": ["type": "string", "pattern": keysPattern]], required: ["keys"]),
        ]
        for kind in registry.kinds {
            let schema = registry.family(for: kind.type)!.schema(kind.type)
            variants.append(variant(kind.type, schema.properties, required: schema.required))
        }
        if allowingContextual {
            variants.append(variant("contextual", [
                "variants": ["type": "object", "additionalProperties": ["$ref": "#/$defs/plainAction"]],
                "fallback": ["$ref": "#/$defs/plainAction"],
            ]))
        }
        return variants
    }

    /// The action types the schema allows, in order.
    public static var actionTypes: [String] {
        actionTypes(registry: .standard)
    }

    public static func actionTypes(registry: ActionRegistry) -> [String] {
        ["application", "open", "exec", "send"] + registry.kinds.map(\.type) + ["contextual"]
    }
}
