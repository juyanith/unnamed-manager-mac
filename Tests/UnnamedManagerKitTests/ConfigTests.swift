import Foundation
import Testing
@testable import UnnamedManagerKit

/// A config from entries and actions given as JSON fragments.
func json(entries: String, actions: String = "{}", contexts: String = "[]", runtime: String = "{}", version: Int = 1) -> String {
    """
    { "version": \(version), "runtime": \(runtime), "entries": [\(entries)], "actions": \(actions), "contexts": \(contexts) }
    """
}

let minimalEntries = """
{ "keys": "Hyper+Space", "title": "Commands" },
{ "keys": "Hyper+Space E", "title": "Editor", "action": "edit" }
"""
let minimalActions = #"{ "edit": { "type": "application", "bundleId": "dev.zed.Zed" } }"#

func load(_ text: String) -> Result<LoadedConfig, ConfigErrors> {
    ConfigLoader.load(Data(text.utf8))
}

func errors(_ text: String) -> [String] {
    if case let .failure(failure) = load(text) { return failure.issues.map(\.message) }
    return []
}

@Suite("Keys")
struct KeyTests {
    @Test("Chords parse in any case and print canonically", arguments: [
        ("hyper+space", "Hyper+Space"),
        ("Ctrl+Alt+L", "Ctrl+Alt+L"),
        ("primary+f", "Cmd+F"),
        ("Shift+Ctrl+pageup", "Ctrl+Shift+PageUp"),
        ("Ctrl+Alt+Shift+Cmd+1", "Hyper+1"),
        ("meh+t", "Meh+T"),
        ("Ctrl+Alt+Shift+T", "Meh+T"),
        ("cag+space", "CAG+Space"),
        ("Cmd+Ctrl+Alt+Space", "CAG+Space"),
        ("Meh+Cmd+A", "Hyper+A"),
        ("CAG+Shift+A", "Hyper+A"),
        ("Ctrl+Shift+Cmd+A", "Ctrl+Shift+Cmd+A"),
        ("Ctrl+Opt+L", "Ctrl+Alt+L"),
        ("control+option+command+K", "CAG+K"),
        ("⌘F", "Cmd+F"),
        ("⌃⌥⇧T", "Meh+T"),
        ("⌃⌥⇧⌘Space", "Hyper+Space"),
        ("⌘+⇧+F", "Shift+Cmd+F"),
        ("⌃⌥+Shift+PageUp", "Meh+PageUp"),
        ("Opt+⌘K", "Alt+Cmd+K"),
        ("f12", "F12"),
    ])
    func chords(_ text: String, expected: String) {
        #expect(Chord(parsing: text)?.description == expected)
    }

    @Test("Unknown names don't parse", arguments: ["Hyper+Spcae", "Meta+A", "Ctrl+", "", "Ctrl+Alt", "⌘", "⌘+", "T⌘", "⌥⌥x+A"])
    func badChords(_ text: String) {
        #expect(Chord(parsing: text) == nil)
    }

    @Test("Key paths split into a leader and steps")
    func paths() throws {
        let path = try #require(KeySequence(parsing: "Hyper+Space  a t"))
        #expect(path.description == "Hyper+Space A T")
        #expect(path.parent?.description == "Hyper+Space A")
        #expect(path.parent?.parent?.isLeader == true)
    }

    @Test("Every key with a code maps back to itself")
    func keyCodes() {
        for key in KeyName.allCases {
            if let code = key.keyCode { #expect(KeyName(keyCode: code) == key) }
        }
        #expect(KeyName.f21.keyCode == nil)
        #expect(KeyName.a.keyCode == 0x00 && KeyName.space.keyCode == 0x31)
    }
}

@Suite("Config loading (S-001)")
struct LoadingTests {
    @Test("A minimal config loads with every default")
    func minimal() throws {
        let loaded = try load(json(entries: minimalEntries, actions: minimalActions)).get()
        #expect(loaded.config.runtime == Config.Runtime())
        #expect(loaded.config.ui == Config.UI())
        #expect(loaded.cancelKey == .escape && loaded.backKey == .backspace)
        #expect(loaded.leaders.count == 1 && loaded.leaders[0].children.count == 1)
        #expect(loaded.warnings.isEmpty)
    }

    @Test("Only version and entries are required")
    func onlyRequired() throws {
        let text = #"{ "version": 1, "entries": [{ "keys": "F13", "title": "Go" }, { "keys": "F13 N", "title": "Nothing", "action": "n" }], "actions": { "n": { "type": "noop" } } }"#
        #expect((try? load(text).get()) != nil)
    }

    @Test("Entry order is kept exactly as in the file")
    func order() throws {
        let entries = """
        { "keys": "Hyper+Space", "title": "Commands" },
        { "keys": "Hyper+Space Z", "title": "Zed", "action": "edit" },
        { "keys": "Hyper+Space A", "title": "Apps" },
        { "keys": "Hyper+Space 1", "title": "One", "action": "edit" },
        { "keys": "Hyper+Space A T", "title": "Terminal", "action": "edit" }
        """
        let leader = try load(json(entries: entries, actions: minimalActions)).get().leaders[0]
        #expect(leader.children.map(\.title) == ["Zed", "Apps", "One"])
        #expect(leader.children[1].children.map(\.title) == ["Terminal"])
    }

    @Test("The starter config loads")
    func starter() throws {
        let loaded = try load(ConfigLoader.starterJSON).get()
        #expect(loaded.leaders.first?.path.description == "Hyper+Space")
        #expect(loaded.leaders.first?.children.map(\.title) == ["Finder", "Terminal"])
        #expect(loaded.leaders.last?.path.description == "Hyper+H")
        #expect(loaded.leaders.last?.action.flatMap { loaded.config.actions[$0] } == .help)
    }

    @Test("The starter is written only when no file exists")
    func starterWrite() throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let url = dir.appending(path: "sub/config.json")
        #expect(try ConfigLoader.writeStarterIfMissing(at: url))
        try Data("{}".utf8).write(to: url)
        #expect(try !ConfigLoader.writeStarterIfMissing(at: url))
        #expect(try String(contentsOf: url, encoding: .utf8) == "{}")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Unused actions and contexts are warnings, not errors")
    func warnings() throws {
        let actions = #"{ "edit": { "type": "application", "bundleId": "x" }, "spare": { "type": "noop" } }"#
        let loaded = try load(json(entries: minimalEntries, actions: actions, contexts: #"[{ "id": "web", "apps": [] }]"#)).get()
        #expect(loaded.warnings.map(\.message) == [
            "Action “spare” isn't used by any binding.",
            "Context “web” isn't used by any action.",
        ])
    }
}

@Suite("Validation rules (SPEC.md)")
struct ValidationTests {
    @Test("Unsupported version")
    func version() {
        #expect(errors(json(entries: minimalEntries, actions: minimalActions, version: 2)).first?.contains("Version 2") == true)
        #expect(errors(#"{ "entries": [] }"#).first?.contains("Missing “version”") == true)
    }

    @Test("Unknown fields name the field and where it is", arguments: [
        (#"{ "version": 1, "entries": [], "extra": 1 }"#, "Unknown field “extra” in the file."),
        (json(entries: #"{ "keys": "Hyper+Space", "title": "C", "colour": "red" }"#), "Unknown field “colour” in entry “Hyper+Space”."),
        (json(entries: minimalEntries, actions: minimalActions, runtime: #"{ "delay": 5 }"#), "Unknown field “delay” in runtime."),
        (json(entries: minimalEntries, actions: #"{ "edit": { "type": "send", "key": "Cmd+F" } }"#), "Unknown field “key” in an action of type “send”."),
    ])
    func unknown(_ text: String, expected: String) {
        #expect(errors(text).first?.hasPrefix(expected) == true)
    }

    @Test("Missing title and unparseable keys")
    func entryShape() {
        #expect(errors(json(entries: #"{ "keys": "Hyper+Space" }"#)).first?.contains("Missing “title”") == true)
        #expect(errors(json(entries: #"{ "keys": "Hyper+Spcae", "title": "C" }"#)).first?.contains("isn't a known name") == true)
    }

    @Test("Duplicate paths, compared case-insensitively")
    func duplicates() {
        let entries = minimalEntries + #", { "keys": "hyper+space e", "title": "Again", "action": "edit" }"#
        #expect(errors(json(entries: entries, actions: minimalActions)).contains("Entries “Hyper+Space E” and “hyper+space e” are the same key path."))
    }

    @Test("Orphans and children of bindings")
    func parents() {
        let orphan = minimalEntries + #", { "keys": "Hyper+Space A T", "title": "T", "action": "edit" }"#
        #expect(errors(json(entries: orphan, actions: minimalActions)).contains { $0.contains("has no parent") })
        let underBinding = minimalEntries + #", { "keys": "Hyper+Space E X", "title": "X", "action": "edit" }"#
        #expect(errors(json(entries: underBinding, actions: minimalActions)).contains { $0.contains("which is a binding") })
    }

    @Test("A top-level entry with an action is a direct binding")
    func directBinding() throws {
        let direct = minimalEntries + #", { "keys": "Hyper+T", "title": "Terminal", "action": "edit" }"#
        let loaded = try load(json(entries: direct, actions: minimalActions)).get()
        #expect(loaded.leaders.map(\.title) == ["Commands", "Terminal"])
        #expect(loaded.leaders[1].action == "edit" && loaded.leaders[1].children.isEmpty)
        // A config of direct bindings alone is fine.
        #expect(errors(json(entries: #"{ "keys": "Hyper+T", "title": "T", "action": "edit" }"#, actions: minimalActions)).isEmpty)
        let under = direct + #", { "keys": "Hyper+T X", "title": "X", "action": "edit" }"#
        #expect(errors(json(entries: under, actions: minimalActions)).contains { $0.contains("which is a binding") })
    }

    @Test("An empty menu")
    func shapes() {
        let empty = minimalEntries + #", { "keys": "Hyper+Space A", "title": "Apps" }"#
        #expect(errors(json(entries: empty, actions: minimalActions)).contains("Menu “Hyper+Space A” has no keys under it. Add a binding or remove the menu."))
    }

    @Test("Step keys with modifiers, or that are the cancel or back key")
    func steps() {
        let modified = minimalEntries + #", { "keys": "Hyper+Space Shift+E", "title": "X", "action": "edit" }"#
        #expect(errors(json(entries: modified, actions: minimalActions)).contains { $0.contains("modifiers on a step key") })
        let cancel = minimalEntries + #", { "keys": "Hyper+Space Escape", "title": "X", "action": "edit" }"#
        #expect(errors(json(entries: cancel, actions: minimalActions)).contains { $0.contains("which is the cancel key") })
        let back = minimalEntries + #", { "keys": "Hyper+Space Backspace", "title": "X", "action": "edit" }"#
        #expect(errors(json(entries: back, actions: minimalActions)).contains { $0.contains("which is the back key") })
    }

    @Test("Cancel and back keys must differ; delays can't be negative")
    func runtime() {
        #expect(errors(json(entries: minimalEntries, actions: minimalActions, runtime: #"{ "cancelKey": "Q", "backKey": "q" }"#))
            .contains { $0.contains("both Q") })
        #expect(errors(json(entries: minimalEntries, actions: minimalActions, runtime: #"{ "hudDelayMs": -1, "timeoutMs": -5 }"#))
            == ["hudDelayMs can't be negative.", "timeoutMs can't be negative."])
    }

    @Test("Position and theme must be known values")
    func uiValues() {
        let text = #"{ "version": 1, "ui": { "position": "left", "theme": "sepia" }, "entries": [\#(minimalEntries)], "actions": \#(minimalActions) }"#
        #expect(errors(text) == [
            "The position “left” isn't one the Guide knows. Use center, top or bottom.",
            "The theme “sepia” isn't one the Guide knows. Use system, light or dark.",
        ])
    }

    @Test("An empty back key turns Back off")
    func noBack() throws {
        #expect(try load(json(entries: minimalEntries, actions: minimalActions, runtime: #"{ "backKey": "" }"#)).get().backKey == nil)
    }

    @Test("A binding that names an undefined action")
    func undefinedAction() {
        #expect(errors(json(entries: minimalEntries)) == ["Binding “Hyper+Space E” uses action “edit”, which isn't defined."])
    }

    @Test("Actions with the wrong fields for their type")
    func actionFields() {
        #expect(errors(json(entries: minimalEntries, actions: #"{ "edit": { "type": "application" } }"#)).first?.contains("Missing “bundleId”") == true)
        #expect(errors(json(entries: minimalEntries, actions: #"{ "edit": { "type": "launch" } }"#)).first?.contains("Unknown action type “launch”") == true)
    }

    @Test("Variants: undefined contexts and nested Context Aware")
    func variants() {
        let undefined = #"{ "edit": { "type": "contextual", "variants": { "web": { "type": "noop" } } } }"#
        #expect(errors(json(entries: minimalEntries, actions: undefined)).contains { $0.contains("context “web”, which isn't defined") })
        let nested = #"{ "edit": { "type": "contextual", "variants": { "web": { "type": "contextual" } } } }"#
        #expect(errors(json(entries: minimalEntries, actions: nested, contexts: #"[{ "id": "web", "apps": [] }]"#))
            .contains { $0.contains("variant inside it") })
    }

    @Test("Two contexts with the same id")
    func duplicateContexts() {
        let contexts = #"[{ "id": "web", "apps": [] }, { "id": "web", "apps": [] }]"#
        #expect(errors(json(entries: minimalEntries, actions: minimalActions, contexts: contexts)).contains { $0.contains("Two contexts are named “web”") })
    }

    @Test("Invalid JSON says so")
    func badJSON() {
        #expect(errors("{ \"version\": 1, ").first?.hasPrefix("The config file isn't valid JSON") == true)
    }
}
