import Foundation

/// One problem in the config file, written as a sentence for the menu bar
/// menu and the Bindings window (S-001, S-008, S-034).
public struct ConfigIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    /// The entry path or action id the issue is about, when there is one.
    public var subject: String?
    /// The spec rule it breaks (S-059). nil for problems outside the file's
    /// contents, such as a file that can't be read.
    public var rule: ConfigRule?

    public init(_ severity: Severity, _ message: String, subject: String? = nil, rule: ConfigRule? = nil) {
        self.severity = severity
        self.message = message
        self.subject = subject
        self.rule = rule
    }

    public var description: String { message }
}

/// A menu or binding in the tree, with its children in file order.
public struct BindingNode: Sendable, Equatable {
    public var path: KeySequence
    public var title: String
    /// The action id; nil for a menu.
    public var action: String?
    /// The entry's own icon (S-056).
    public var icon: String? = nil
    public var children: [BindingNode]

    public var isMenu: Bool { action == nil }

    /// The child selected by a step key, if any.
    public func child(for key: KeyName) -> BindingNode? {
        children.first { $0.path.lastStep?.key == key }
    }
}

/// A valid config, ready to use: the tree of leaders and the resolved keys.
/// A top-level entry with an action is a direct binding: its chord runs the
/// action at once, with no sequence.
public struct LoadedConfig: Sendable, Equatable {
    public var config: Config
    /// Top-level entries in file order: leaders (menus) and direct bindings.
    public var leaders: [BindingNode]
    public var cancelKey: KeyName
    /// nil when Back is turned off.
    public var backKey: KeyName?
    /// Unused actions and contexts. They never stop a config from loading.
    public var warnings: [ConfigIssue]

    public func leader(for chord: Chord) -> BindingNode? {
        leaders.first { $0.path.leader == chord }
    }
}

/// Checks every rule in SPEC.md, Validation.
public enum ConfigValidator {
    /// Returns the loaded config, or every error found.
    public static func validate(_ config: Config) -> Result<LoadedConfig, ConfigErrors> {
        var errors: [ConfigIssue] = []
        func error(_ rule: ConfigRule, _ message: String, _ subject: String? = nil) {
            errors.append(ConfigIssue(.error, message, subject: subject, rule: rule))
        }

        if config.version != Config.supportedVersion {
            error(.version, "Version \(config.version) isn't supported. Use \"version\": \(Config.supportedVersion).")
        }

        // Cancel and back keys.
        let cancelKey = KeyName(parsing: config.runtime.cancelKey)
        if cancelKey == nil { error(.badRuntimeKey, "The cancel key “\(config.runtime.cancelKey)” isn't a key name.") }
        var backKey: KeyName?
        if !config.runtime.backKey.isEmpty {
            backKey = KeyName(parsing: config.runtime.backKey)
            if backKey == nil { error(.badRuntimeKey, "The back key “\(config.runtime.backKey)” isn't a key name.") }
        }
        if let cancelKey, cancelKey == backKey {
            error(.sameCancelBack, "The cancel key and the back key are both \(cancelKey.name). Choose two different keys.")
        }
        if config.runtime.hudDelayMs < 0 { error(.negativeDelay, "hudDelayMs can't be negative.") }
        if !["center", "top", "bottom"].contains(config.ui.position.lowercased()) {
            error(.badUIValue, "The position “\(config.ui.position)” isn't one the Guide knows. Use center, top or bottom.")
        }
        if !["system", "light", "dark"].contains(config.ui.theme.lowercased()) {
            error(.badUIValue, "The theme “\(config.ui.theme)” isn't one the Guide knows. Use system, light or dark.")
        }
        if config.runtime.timeoutMs < 0 { error(.negativeDelay, "timeoutMs can't be negative.") }

        // Entries: parse, find duplicates.
        var parsed: [(entry: Config.Entry, path: KeySequence)] = []
        var seen: [KeySequence: String] = [:]
        if config.entries.isEmpty { error(.noEntries, "The config has no entries. Add a leader and at least one binding, or a direct binding.") }
        for entry in config.entries {
            guard let path = KeySequence(parsing: entry.keys) else {
                error(.badKeys, "Entry “\(entry.keys)” has a key that isn't a known name. Check the spelling of each key and modifier.", entry.keys)
                continue
            }
            if entry.title.trimmingCharacters(in: .whitespaces).isEmpty {
                error(.emptyTitle, "Entry “\(path)” has an empty title.", path.description)
            }
            if let first = seen[path] {
                error(.duplicatePath, "Entries “\(first)” and “\(entry.keys)” are the same key path.", path.description)
                continue
            }
            seen[path] = entry.keys
            parsed.append((entry, path))
        }

        let byPath = Dictionary(uniqueKeysWithValues: parsed.map { ($0.path, $0.entry) })
        var childCount: [KeySequence: Int] = [:]
        for (entry, path) in parsed {
            let name = entry.action == nil ? "Menu" : "Binding"
            if path.parent == nil, path.leader.isKeptByMacOS {
                error(.reservedChord, "\(entry.action == nil ? "Leader" : "Direct binding") “\(path)” uses a chord macOS keeps for its diagnostics (sysdiagnose), so Unnamed Manager never sees it. Choose another key.", path.description)
            }
            if let parent = path.parent {
                guard let parentEntry = byPath[parent] else {
                    error(.noParent, "\(name) “\(path)” has no parent. Add an entry for “\(parent)”.", path.description)
                    continue
                }
                if parentEntry.action != nil {
                    error(.parentIsBinding, "\(name) “\(path)” is under “\(parent)”, which is a binding. Only menus can have keys under them.", path.description)
                }
                childCount[parent, default: 0] += 1
                if let step = path.lastStep {
                    if !step.modifiers.isEmpty {
                        error(.stepModifiers, "\(name) “\(path)” uses modifiers on a step key. Only the leader can have modifiers.", path.description)
                    }
                    if step.key == cancelKey || step.key == backKey {
                        error(.stepIsRuntimeKey, "\(name) “\(path)” uses \(step.key.name), which is the \(step.key == cancelKey ? "cancel" : "back") key.", path.description)
                    }
                }
            }
            if let action = entry.action, config.actions[action] == nil {
                error(.undefinedAction, "Binding “\(path)” uses action “\(action)”, which isn't defined.", path.description)
            }
        }
        for (entry, path) in parsed where entry.action == nil && childCount[path, default: 0] == 0 {
            error(.emptyMenu, "Menu “\(path)” has no keys under it. Add a binding or remove the menu.", path.description)
        }

        // Contexts and actions.
        var contextIDs = Set<String>()
        for context in config.contexts {
            if !contextIDs.insert(context.id).inserted {
                error(.duplicateContext, "Two contexts are named “\(context.id)”. Give each context its own id.", context.id)
            }
        }
        var usedContexts = Set<String>()
        for id in config.actions.keys.sorted() {
            guard case let .contextual(variants, fallback) = config.actions[id] else { continue }
            for contextID in variants.keys.sorted() {
                usedContexts.insert(contextID)
                if !contextIDs.contains(contextID) {
                    error(.undefinedContext, "Action “\(id)” has a variant for context “\(contextID)”, which isn't defined.", id)
                }
                if case .contextual = variants[contextID] {
                    error(.nestedContextual, "Action “\(id)” has a Context Aware variant inside it. Variants must be other kinds of action.", id)
                }
            }
            if case .contextual = fallback {
                error(.nestedContextual, "Action “\(id)” has a Context Aware fallback. The fallback must be another kind of action.", id)
            }
        }

        guard errors.isEmpty, let cancelKey else { return .failure(ConfigErrors(issues: errors)) }

        var warnings: [ConfigIssue] = []
        let usedActions = Set(config.entries.compactMap(\.action))
        for id in config.actions.keys.sorted() where !usedActions.contains(id) {
            warnings.append(ConfigIssue(.warning, "Action “\(id)” isn't used by any binding.", subject: id, rule: .unusedAction))
        }
        for context in config.contexts where !usedContexts.contains(context.id) {
            warnings.append(ConfigIssue(.warning, "Context “\(context.id)” isn't used by any action.", subject: context.id, rule: .unusedContext))
        }
        for (_, path) in parsed where ([path.leader] + path.steps).contains(where: { $0.key.keyCode == nil }) {
            warnings.append(ConfigIssue(.warning, "Entry “\(path)” uses a key a Mac keyboard doesn't have.", subject: path.description, rule: .keyNotOnPlatform))
        }

        return .success(LoadedConfig(config: config, leaders: tree(parsed), cancelKey: cancelKey,
                                     backKey: backKey, warnings: warnings))
    }

    /// Builds the tree, keeping file order at every level.
    private static func tree(_ parsed: [(entry: Config.Entry, path: KeySequence)]) -> [BindingNode] {
        func node(_ item: (entry: Config.Entry, path: KeySequence)) -> BindingNode {
            let children = parsed.filter { $0.path.parent == item.path }.map(node)
            return BindingNode(path: item.path, title: item.entry.title, action: item.entry.action,
                               icon: item.entry.icon, children: children)
        }
        return parsed.filter { $0.path.isLeader }.map(node)
    }
}

/// Every error that stopped a config from loading, in file order.
public struct ConfigErrors: Error, Sendable, Equatable {
    public var issues: [ConfigIssue]
    public init(issues: [ConfigIssue]) { self.issues = issues }
}
