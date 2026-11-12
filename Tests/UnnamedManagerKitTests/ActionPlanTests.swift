import Foundation
import Testing
@testable import UnnamedManagerKit

let testHome = URL(fileURLWithPath: "/Users/someone")

@Suite("Open (S-010)")
struct OpenPlanTests {
    @Test("A leading ~ expands to the home folder, and nothing else is expanded", arguments: [
        ("~", "/Users/someone"),
        ("~/notes", "/Users/someone/notes"),
        ("~notes", "~notes"),
        ("~other/notes", "~other/notes"),
        ("/tmp/~/x", "/tmp/~/x"),
        ("$HOME/notes", "$HOME/notes"),
        ("notes/*.md", "notes/*.md"),
    ])
    func tilde(_ input: String, expected: String) {
        #expect(ActionPlanner.expandTilde(input, home: testHome) == expected)
    }

    @Test("Paths become file URLs and URLs stay URLs")
    func targets() throws {
        #expect(try ActionPlanner.plan(.open(target: "~/notes"), home: testHome) == .open(URL(fileURLWithPath: "/Users/someone/notes")))
        #expect(try ActionPlanner.plan(.open(target: "/Applications"), home: testHome) == .open(URL(fileURLWithPath: "/Applications")))
        #expect(try ActionPlanner.plan(.open(target: "https://example.com"), home: testHome) == .open(URL(string: "https://example.com")!))
        #expect(try ActionPlanner.plan(.open(target: "mailto:a@b.c"), home: testHome) == .open(URL(string: "mailto:a@b.c")!))
    }

    @Test("A relative path is an error, not a guess")
    func relative() {
        #expect(throws: PlanError.self) { try ActionPlanner.plan(.open(target: "notes"), home: testHome) }
    }
}

@Suite("Do Nothing (S-014)")
struct NoopPlanTests {
    @Test("A noop plans nothing")
    func noop() throws {
        #expect(try ActionPlanner.plan(.noop, home: testHome) == .nothing)
    }
}

@Suite("Show Help (S-053)")
struct HelpPlanTests {
    @Test("Show Help plans opening the Help page")
    func help() throws {
        #expect(try ActionPlanner.plan(.help, home: testHome) == .showHelp)
    }

    @Test("Show Help reads from the file, takes no fields, and is written back")
    func roundTrip() throws {
        let text = json(entries: #"{ "keys": "Hyper+H", "title": "Help", "action": "show-help" }"#,
                        actions: #"{ "show-help": { "type": "help" } }"#)
        let config = try load(text).get()
        #expect(config.config.actions["show-help"] == .help)
        #expect(config.config.actions["show-help"]?.displayName == "Show Help")
        let written = String(decoding: ConfigDocument(config: config.config).data(), as: UTF8.self)
        #expect(try load(written).get().config.actions["show-help"] == .help)
        #expect(!errors(json(entries: #"{ "keys": "Hyper+H", "title": "Help", "action": "h" }"#,
                             actions: #"{ "h": { "type": "help", "page": "keys" } }"#)).isEmpty)
    }

    @Test("A Show Help direct binding runs from its chord")
    func direct() throws {
        let text = json(entries: #"{ "keys": "Hyper+H", "title": "Help", "action": "show-help" }"#,
                        actions: #"{ "show-help": { "type": "help" } }"#)
        var engine = SequenceEngine(config: try load(text).get())
        guard case let .run(binding, _) = engine.handle(.down(keyCode: KeyName.h.keyCode!, modifiers: .hyper, isRepeat: false)).effect else {
            Issue.record("no run"); return
        }
        #expect(binding.title == "Help")
        #expect(!engine.isActive)
    }
}

@Suite("Chords macOS keeps")
struct KeptByMacOSTests {
    @Test("Hyper+Comma, Hyper+Period and Hyper+Slash can't be leaders or direct bindings", arguments: ["Comma", "Period", "Slash"])
    func rejected(_ key: String) {
        let found = errors(json(entries: #"{ "keys": "Hyper+\#(key)", "title": "Help", "action": "h" }"#,
                                actions: #"{ "h": { "type": "help" } }"#))
        #expect(found.contains { $0.contains("macOS keeps for its diagnostics") }, "\(found)")
    }

    @Test("Other modifiers on those keys, and those keys in a menu, are fine")
    func allowed() throws {
        _ = try load(json(entries: """
            { "keys": "Meh+Slash", "title": "Help", "action": "h" },
            { "keys": "Hyper+Space", "title": "Commands" },
            { "keys": "Hyper+Space Period", "title": "Help", "action": "h" }
            """, actions: #"{ "h": { "type": "help" } }"#)).get()
    }

    @Test("The key recorder refuses them for a leader")
    func recorder() throws {
        let document = ConfigDocument(config: try load(json(entries: #"{ "keys": "Hyper+H", "title": "Help", "action": "h" }"#,
                                                             actions: #"{ "h": { "type": "help" } }"#)).get().config)
        let path = KeySequence(parsing: "Hyper+H")!
        #expect(document.keyProblem(for: path, newKey: Chord(modifiers: .hyper, key: .slash)) == .keptByMacOS("Hyper+Slash"))
        #expect(document.keyProblem(for: path, newKey: Chord(modifiers: .meh, key: .slash)) == nil)
    }
}

@Suite("Run Command (S-011)")
struct ExecPlanTests {
    @Test("Arguments pass literally; only a leading ~ in command and cwd expands")
    func literal() throws {
        let plan = try ActionPlanner.plan(.exec(command: ["~/bin/tool", "~/notes", "$HOME", "*.md", "a b", "x~/y"],
                                                cwd: "~/work", env: ["K": "~/v"]), home: testHome)
        #expect(plan == .spawn(program: "/Users/someone/bin/tool",
                               arguments: ["/Users/someone/notes", "$HOME", "*.md", "a b", "x~/y"],
                               cwd: URL(fileURLWithPath: "/Users/someone/work", isDirectory: true),
                               env: ["K": "~/v"]))
    }

    @Test("cwd defaults to the home folder")
    func defaultCwd() throws {
        guard case let .spawn(_, _, cwd, _) = try ActionPlanner.plan(.exec(command: ["zed"], cwd: nil, env: [:]), home: testHome) else {
            Issue.record("not a spawn"); return
        }
        #expect(cwd == testHome)
    }

    @Test("An empty command is an error")
    func empty() {
        #expect(throws: PlanError.self) { try ActionPlanner.plan(.exec(command: [], cwd: nil, env: [:]), home: testHome) }
    }

    @Test("Programs are found in the search path, in order; paths are checked as given")
    func locate() {
        let files: Set<String> = ["/opt/homebrew/bin/zed", "/usr/local/bin/zed", "/usr/bin/true"]
        let path = ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        #expect(ActionPlanner.locate("zed", searchPath: path, isExecutable: files.contains) == "/opt/homebrew/bin/zed")
        #expect(ActionPlanner.locate("/usr/bin/true", searchPath: [], isExecutable: files.contains) == "/usr/bin/true")
        #expect(ActionPlanner.locate("nope", searchPath: path, isExecutable: files.contains) == nil)
    }

    @Test("The search path keeps PATH first and adds the usual folders once")
    func searchPath() {
        let dirs = ActionPlanner.searchPath(environmentPath: "/usr/bin:/bin:/custom", home: testHome)
        #expect(Array(dirs.prefix(3)) == ["/usr/bin", "/bin", "/custom"])
        #expect(dirs.contains("/opt/homebrew/bin") && dirs.contains("/Users/someone/.local/bin"))
        #expect(dirs.filter { $0 == "/usr/bin" }.count == 1)
    }
}

@Suite("Send Shortcut (S-012)")
struct SendPlanTests {
    @Test("send parses one or more chords, and Primary maps to ⌘")
    func chords() throws {
        #expect(try ActionPlanner.plan(.send(keys: "Primary+F"), home: testHome) == .send([Chord(modifiers: .command, key: .f)]))
        #expect(try ActionPlanner.chords("Cmd+K  S") == [Chord(modifiers: .command, key: .k), Chord(key: .s)])
        #expect(try ActionPlanner.chords("Hyper+1") == [Chord(modifiers: .hyper, key: .d1)])
    }

    @Test("Bad or empty keys are errors", arguments: ["", "Cmd+Spcae", "Super+F"])
    func bad(_ keys: String) {
        #expect(throws: PlanError.self) { try ActionPlanner.chords(keys) }
    }
}

@Suite("Context Aware (S-013)")
struct ContextTests {
    let contexts = [
        Config.Context(id: "browser", apps: ["com.google.Chrome", "com.apple.Safari"]),
        Config.Context(id: "chromium", apps: ["com.google.Chrome"]),
        Config.Context(id: "editor", apps: ["dev.zed.Zed"]),
    ]
    let cmdL = Config.Action.send(keys: "Cmd+L")
    let chromeOnly = Config.Action.send(keys: "Cmd+Shift+L")
    let cmdF = Config.Action.send(keys: "Cmd+F")

    @Test("The first context in contexts order with the app and a variant wins")
    func order() {
        let action = Config.Action.contextual(variants: ["chromium": chromeOnly, "browser": cmdL], fallback: cmdF)
        #expect(ContextResolver.resolve(action, frontApp: "com.google.Chrome", contexts: contexts) == cmdL)
        #expect(ContextResolver.resolve(action, frontApp: "com.apple.Safari", contexts: contexts) == cmdL)
        // A context with the app but no variant is skipped.
        let skip = Config.Action.contextual(variants: ["chromium": chromeOnly], fallback: nil)
        #expect(ContextResolver.resolve(skip, frontApp: "com.google.Chrome", contexts: contexts) == chromeOnly)
    }

    @Test("Otherwise the fallback runs; with no fallback the action is unavailable")
    func fallback() {
        let withFallback = Config.Action.contextual(variants: ["browser": cmdL], fallback: cmdF)
        #expect(ContextResolver.resolve(withFallback, frontApp: "com.apple.Notes", contexts: contexts) == cmdF)
        #expect(ContextResolver.resolve(withFallback, frontApp: nil, contexts: contexts) == cmdF)
        let without = Config.Action.contextual(variants: ["browser": cmdL], fallback: nil)
        #expect(ContextResolver.resolve(without, frontApp: "com.apple.Notes", contexts: contexts) == nil)
    }

    @Test("Other kinds of action are always available")
    func plain() {
        #expect(ContextResolver.resolve(cmdF, frontApp: nil, contexts: []) == cmdF)
    }
}

@Suite("Context Aware in a sequence (S-013)")
struct ContextSequenceTests {
    let text = json(entries: """
    { "keys": "Hyper+Space", "title": "Commands" },
    { "keys": "Hyper+Space L", "title": "Address Bar", "action": "address" }
    """, actions: #"{ "address": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Cmd+L" } } } }"#,
    contexts: #"[{ "id": "browser", "apps": ["com.apple.Safari"] }]"#)

    func start(in app: String) throws -> SequenceEngine {
        var engine = SequenceEngine(config: try load(text).get())
        engine.setFrontApp(app)
        _ = engine.handle(.down(keyCode: KeyName.space.keyCode!, modifiers: .hyper, isRepeat: false))
        return engine
    }

    @Test("Pressing an unavailable binding gives error feedback, runs nothing, and stays")
    func unavailable() throws {
        var engine = try start(in: "com.apple.Notes")
        let output = engine.handle(.down(keyCode: KeyName.l.keyCode!, modifiers: [], isRepeat: false))
        guard case let .unavailable(binding, path) = output.effect else { Issue.record("\(String(describing: output.effect))"); return }
        #expect(output.consume && binding.title == "Address Bar" && path == ["Commands"] && engine.isActive)
    }

    @Test("In a matching app the binding runs, for the app that was in front at the leader")
    func available() throws {
        var engine = try start(in: "com.apple.Safari")
        // Switching apps mid-sequence doesn't change the answer.
        engine.setFrontApp("com.apple.Notes")
        guard case let .run(binding, frontApp) = engine.handle(.down(keyCode: KeyName.l.keyCode!, modifiers: [], isRepeat: false)).effect else {
            Issue.record("no run"); return
        }
        #expect(binding.title == "Address Bar" && frontApp == "com.apple.Safari")
    }
}

@Suite("Context Aware direct bindings")
struct ContextDirectTests {
    let text = json(entries: #"{ "keys": "Hyper+L", "title": "Address Bar", "action": "address" }"#,
                    actions: #"{ "address": { "type": "contextual", "variants": { "browser": { "type": "send", "keys": "Cmd+L" } } } }"#,
                    contexts: #"[{ "id": "browser", "apps": ["com.apple.Safari"] }]"#)

    func press(in app: String) throws -> SequenceOutput {
        var engine = SequenceEngine(config: try load(text).get())
        engine.setFrontApp(app)
        return engine.handle(.down(keyCode: KeyName.l.keyCode!, modifiers: .hyper, isRepeat: false))
    }

    @Test("In a matching app it runs for that app")
    func available() throws {
        guard case let .run(_, frontApp) = try press(in: "com.apple.Safari").effect else { Issue.record("no run"); return }
        #expect(frontApp == "com.apple.Safari")
    }

    @Test("With nothing to run, the chord goes through to the app in front")
    func unavailable() throws {
        #expect(try press(in: "com.apple.Notes") == .pass)
    }
}

@Suite("Do Nothing in a sequence (S-014)")
struct NoopSequenceTests {
    @Test("A noop binding ends the sequence and does nothing else")
    func noop() throws {
        let text = json(entries: """
        { "keys": "Hyper+Space", "title": "Commands" },
        { "keys": "Hyper+Space R", "title": "Reserved", "action": "reserved" }
        """, actions: #"{ "reserved": { "type": "noop" } }"#)
        let config = try load(text).get()
        var engine = SequenceEngine(config: config)
        _ = engine.handle(.down(keyCode: KeyName.space.keyCode!, modifiers: .hyper, isRepeat: false))
        guard case let .run(binding, _) = engine.handle(.down(keyCode: KeyName.r.keyCode!, modifiers: [], isRepeat: false)).effect else {
            Issue.record("no run"); return
        }
        #expect(!engine.isActive)
        #expect(try ActionPlanner.plan(config.config.actions[binding.action!]!, home: testHome) == .nothing)
    }
}

@Suite("Use Application modes (S-046)")
struct UseApplicationTests {
    @Test("Each mode plans its own way of opening the app")
    func plans() throws {
        #expect(try ActionPlanner.plan(.application(bundleId: "dev.zed.Zed"), home: testHome) == .openApp(bundleId: "dev.zed.Zed"))
        #expect(try ActionPlanner.plan(.application(bundleId: "dev.zed.Zed", mode: .focus), home: testHome) == .focusApp(bundleId: "dev.zed.Zed"))
        #expect(try ActionPlanner.plan(.application(bundleId: "dev.zed.Zed", mode: .start), home: testHome) == .startApp(bundleId: "dev.zed.Zed"))
    }

    @Test("A file without mode means Focus or Start")
    func defaultMode() throws {
        let config = try load(json(entries: minimalEntries, actions: minimalActions)).get()
        #expect(config.config.actions["edit"] == .application(bundleId: "dev.zed.Zed", mode: .focusOrStart))
    }

    @Test("mode is read from the file, and an unknown one is an error")
    func readMode() throws {
        let focus = #"{ "edit": { "type": "application", "bundleId": "dev.zed.Zed", "mode": "focus" } }"#
        #expect(try load(json(entries: minimalEntries, actions: focus)).get().config.actions["edit"]
                == .application(bundleId: "dev.zed.Zed", mode: .focus))
        let bad = #"{ "edit": { "type": "application", "bundleId": "dev.zed.Zed", "mode": "launch" } }"#
        #expect(errors(json(entries: minimalEntries, actions: bad)).first?.contains("Unknown mode “launch”") == true)
    }

    @Test("mode is written only when it isn't the default")
    func writeMode() {
        #expect(!ConfigWriter.action(.application(bundleId: "a"), contexts: []).contains("mode"))
        #expect(ConfigWriter.action(.application(bundleId: "a", mode: .start), contexts: []).contains(#""mode": "start""#))
    }

    @Test("The schema lists every mode")
    func schema() {
        #expect(ConfigSchema.json.contains(#""focusOrStart""#) && ConfigSchema.json.contains(#""focus""#)
                && ConfigSchema.json.contains(#""start""#))
    }
}
