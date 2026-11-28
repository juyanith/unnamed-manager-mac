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
                "windows": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "gap": ["type": "number", "minimum": 0, "description": "Points Place Window and Fill leave around windows and between them. Default 8."],
                        "minCell": steps("The smallest cell Arrange Windows makes, in steps, across and down. It sets the most columns and rows. Default 6 by 6."),
                        "displays": [
                            "type": "object",
                            "description": "Settings for each display, keyed by its size in points after scaling, such as \"3840x1080\".",
                            "propertyNames": ["pattern": "^[1-9][0-9]*x[1-9][0-9]*$"],
                            "additionalProperties": ["type": "object", "additionalProperties": false, "properties": [
                                "steps": steps("How many steps cut this display's usable area, in place of the guess: 12 on the short side, and 12 on the long side for each whole time the short side fits into it."),
                                "minCell": steps("In place of windows.minCell on this display."),
                            ]],
                        ],
                        "maxColumns": ["type": "integer", "minimum": Config.Windows.limitRange.lowerBound, "maximum": Config.Windows.limitRange.upperBound,
                                       "description": "Retired in spec v24: does nothing, and loads with a warning. windows.minCell takes its place."],
                        "maxRows": ["type": "integer", "minimum": Config.Windows.limitRange.lowerBound, "maximum": Config.Windows.limitRange.upperBound,
                                    "description": "Retired in spec v24: does nothing, and loads with a warning. windows.minCell takes its place."],
                        "minVisible": ["type": "number", "minimum": 0, "description": "Points on a side of the square a window must show for Focus Window and Swap Window to count it, and points it must share with the focused window to be in line. Default 20."],
                        "rowTolerance": ["type": "number", "minimum": 0, "description": "Windows whose tops are within this many points share a row in Focus Window's order. Default 20."],
                        "tieTolerance": ["type": "number", "minimum": 0, "description": "Gaps within this many points count as the same when Focus Window picks a window in a direction. Default 2."],
                        "quitOnClose": ["type": "boolean", "description": "Mac only. Closing an app's last window also quits the app. Finder is never quit. Default false."],
                        "quitOnCloseDelayMs": ["type": "integer", "minimum": 0, "description": "Mac only. Milliseconds after a window closes before Quit on close counts the app's windows. Default 500."],
                        "apps": [
                            "type": "object",
                            "description": "Rules for each app's windows, keyed by app id. Mac: bundle ids. Windows: an exe (ends in .exe) or an AppUserModelID. An app that isn't listed takes part in every window action.",
                            "additionalProperties": ["type": "object", "additionalProperties": false, "properties": [
                                "focus": ["type": "boolean", "description": "false: Focus Window never picks this app's windows. Default true."],
                                "swap": ["type": "boolean", "description": "false: Swap Window never moves this app's windows. Default true."],
                                "arrange": ["type": "boolean", "description": "false: Arrange Windows never counts or moves this app's windows. Default true."],
                                "quit": ["type": "boolean", "description": "Mac only. false: Quit on close never quits this app. Default true."],
                                "minWidth": ["type": "number", "minimum": 0, "description": "The smallest width, in points, Arrange Windows and Tidy Windows give this app's windows, rounded up to whole steps. 0 (default) sets none."],
                                "minHeight": ["type": "number", "minimum": 0, "description": "The smallest height, in points, Arrange Windows and Tidy Windows give this app's windows, rounded up to whole steps. 0 (default) sets none."],
                            ]],
                        ],
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
                            "hold": ["type": "boolean",
                                     "description": "Spec v18. Leaders only: true makes this leader's menu, and every menu under it, a held menu. Hold the modifiers, move the highlight with the key that opened the menu (Shift goes back), and let go to choose. The leader needs at least one modifier."],
                            "list": listSchema,
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

    /// Steps across and down, both required (spec v24).
    private static func steps(_ description: String) -> [String: Any] {
        let count: [String: Any] = ["type": "integer", "minimum": WindowSteps.range.lowerBound, "maximum": WindowSteps.range.upperBound]
        return ["type": "object", "additionalProperties": false, "required": ["across", "down"],
                "properties": ["across": count, "down": count], "description": description]
    }

    /// An entry's `list` (spec v18), as the spec's schema has it.
    private static var listSchema: [String: Any] {
        let recent: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["type"],
            "properties": [
                "type": ["const": Config.List.recentWindows, "description": "Recent Windows: the windows used last, most recent first."],
                "count": ["type": "integer", "minimum": Config.List.countRange.lowerBound, "maximum": Config.List.countRange.upperBound,
                          "default": 9, "description": "The most items. Keys 1 to 9 on each page, and 0 for More."],
                "minimized": ["type": "boolean", "default": true, "description": "Include minimized windows."],
                "hidden": ["type": "boolean", "default": true, "description": "Mac only. Include the windows of hidden apps."],
                "spaces": ["enum": ["all", "current"], "default": "all",
                           "description": "all: windows on every Space or desktop. current: only the current one of each display."],
                "scope": ["enum": ["all", "display"], "default": "all",
                          "description": "all: every display. display: only the focused window's display."],
                "choose": ["enum": Config.List.chooseValues, "default": "focus",
                           "description": "Spec v19. What choosing an item does. focus: go to its window. swap: trade places with it, as Swap Window does; then minimized, hidden and spaces don't apply."],
            ] as [String: Any],
        ]
        return ["description": "Spec v18. Makes this menu a list: the app fills it when it opens, so it has no entries under it and no action.",
                "oneOf": [recent]]
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
        var variants: [[String: Any]] = []
        for kind in registry.kinds {
            let schema = registry.family(for: kind.type)!.schema(kind.type)
            for shape in [schema] + schema.alternatives {
                variants.append(variant(kind.type, shape.properties, required: shape.required))
            }
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
        registry.kinds.map(\.type) + ["contextual"]
    }
}
