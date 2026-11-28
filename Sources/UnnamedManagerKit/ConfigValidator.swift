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
    /// A leader whose menus are held menus (spec v18).
    public var hold = false
    /// A list the app fills when it opens (spec v18). Its children are its items once filled.
    public var list: Config.List? = nil
    /// One item of a filled list: the window it goes to.
    public var item: ListItem? = nil
    /// In a filled list, the focused window, which Cancel shows (spec v18).
    public var front: ListItem? = nil
    public var children: [BindingNode]

    /// A list's item has no action but runs, like a binding.
    public var isMenu: Bool { action == nil && item == nil }

    /// Every item of a filled list, on every page (S-093).
    public var items: [ListItem] = []
    /// The page of a filled list its children show, from 0.
    public var page = 0

    /// Items on one page of a list: keys 1 to 9 (spec v18).
    public static let pageSize = KeyName.itemKeys.count
    public var pageCount: Int { max(1, (items.count + Self.pageSize - 1) / Self.pageSize) }
    /// A list with a page after this one has More, on key 0.
    public var hasMore: Bool { list != nil && page < pageCount - 1 }

    /// A list filled with `items`, on its first page.
    public func filled(with items: [ListItem], front: ListItem?) -> BindingNode {
        var node = self
        node.items = items
        node.front = front
        return node.onPage(0)
    }

    /// The list on another page: its children are that page's items, keys 1 to 9.
    public func onPage(_ page: Int) -> BindingNode {
        var node = self
        node.page = min(max(page, 0), pageCount - 1)
        let start = node.page * Self.pageSize
        node.children = zip(KeyName.itemKeys, items[start..<min(start + Self.pageSize, items.count)]).map { key, item in
            BindingNode(path: KeySequence(leader: path.leader, steps: path.steps + [Chord(modifiers: [], key: key)]),
                        title: item.title, action: nil, item: item, children: [])
        }
        return node
    }

    /// The key that opened this menu: the leader chord's key, or its own
    /// step key. In a held menu it moves the highlight (spec v18).
    public var repeatKey: KeyName { path.lastStep?.key ?? path.leader.key }

    /// The child selected by a step key, if any.
    public func child(for key: KeyName) -> BindingNode? {
        children.first { $0.path.lastStep?.key == key }
    }

    /// Its title in the path: a list with pages adds the page (S-093).
    public var pathTitles: [String] {
        list != nil && pageCount > 1 ? [title, "Page \(page + 1) of \(pageCount)"] : [title]
    }
}

/// One item of a list, as the app found it when the list opened (spec v18).
public struct ListItem: Sendable, Equatable {
    /// How the app finds the window again.
    public var id: Int
    /// The window's title, or its app's name when it has none.
    public var title: String
    /// Its app's bundle id, for the icon.
    public var app: String?
    public var marks: Marks

    public init(id: Int, title: String, app: String? = nil, marks: Marks = []) {
        self.id = id
        self.title = title
        self.app = app
        self.marks = marks
    }

    /// What the Guide marks on an item.
    public struct Marks: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let minimized = Marks(rawValue: 1)
        public static let hidden = Marks(rawValue: 2)
        public static let otherSpace = Marks(rawValue: 4)
        public static let otherDisplay = Marks(rawValue: 8)
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
        if config.windows.quitOnCloseDelayMs < 0 { error(.negativeDelay, "quitOnCloseDelayMs can't be negative.") }
        if config.windows.gap < 0 { error(.negativeGap, "The gap between windows can't be negative.") }
        let limits = Config.Windows.limitRange
        for (name, value) in [("maxColumns", config.windows.maxColumns), ("maxRows", config.windows.maxRows)] {
            if let value, !limits.contains(value) {
                error(.badWindowLimit, "\(name) must be from \(limits.lowerBound) to \(limits.upperBound).")
            }
        }
        // Steps and smallest cells (spec v24).
        var counts = [("windows.minCell", config.windows.minCell)]
        for (key, display) in config.windows.displays.sorted(by: { $0.key < $1.key }) {
            if !Config.Windows.isDisplayKey(key) {
                error(.badDisplayKey, "The display “\(key)” in windows.displays isn't a width, an x and a height in points, such as \"3840x1080\".", key)
            }
            if let steps = display.steps { counts.append(("steps for display \(key)", steps)) }
            if let cell = display.minCell { counts.append(("minCell for display \(key)", cell)) }
        }
        let range = WindowSteps.range
        for (name, value) in counts where !range.contains(value.across) || !range.contains(value.down) {
            error(.badWindowLimit, "The across and down of \(name) must be from \(range.lowerBound) to \(range.upperBound).")
        }
        let distances = [("minVisible", config.windows.minVisible), ("rowTolerance", config.windows.rowTolerance), ("tieTolerance", config.windows.tieTolerance)]
        for (name, value) in distances where value < 0 {
            error(.negativeWindowDistance, "\(name) can't be negative.")
        }
        for (app, rules) in config.windows.apps.sorted(by: { $0.key < $1.key }) where rules.minWidth < 0 || rules.minHeight < 0 {
            error(.negativeWindowDistance, "The smallest size for \(app) in windows.apps can't be negative.", app)
        }

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
                } else if parentEntry.list != nil {
                    error(.listHasChildren, "\(name) “\(path)” is under “\(parent)”, which is a list. The app fills a list itself, so remove this entry.", path.description)
                }
                childCount[parent, default: 0] += 1
                if let step = path.lastStep {
                    if !step.modifiers.isEmpty {
                        error(.stepModifiers, "\(name) “\(path)” uses modifiers on a step key. Only the leader can have modifiers.", path.description)
                    }
                    if step.key == cancelKey || step.key == backKey {
                        error(.stepIsRuntimeKey, "\(name) “\(path)” uses \(step.key.name), which is the \(step.key == cancelKey ? "cancel" : "back") key.", path.description)
                    }
                    let repeatKey = parent.lastStep?.key ?? parent.leader.key
                    if byPath[KeySequence(leader: path.leader)]?.hold == true, step.key == repeatKey {
                        error(.stepIsRepeatKey, "\(name) “\(path)” uses \(step.key.name), which moves the highlight in the held menu “\(parent)”. Choose another key.", path.description)
                    }
                }
            }
            if entry.hold {
                if !path.isLeader || entry.action != nil {
                    error(.holdNotLeader, "\(name) “\(path)” has Hold, but only a leader can have it.", path.description)
                } else if path.leader.modifiers.isEmpty {
                    error(.holdNoModifiers, "Leader “\(path)” has Hold but no modifiers, so there's nothing to let go of. Add a modifier, or turn Hold off.", path.description)
                }
            }
            if let action = entry.action, config.action(named: action) == nil {
                error(.undefinedAction, "Binding “\(path)” uses action “\(action)”, which isn't defined or built in.", path.description)
            }
            if let list = entry.list {
                checkList(list, at: path, hasAction: entry.action != nil,
                          held: byPath[KeySequence(leader: path.leader)]?.hold == true, error)
            }
        }
        // A list is never empty: the app fills it.
        for (entry, path) in parsed where entry.action == nil && entry.list == nil && childCount[path, default: 0] == 0 {
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
        for (name, value) in [("maxColumns", config.windows.maxColumns), ("maxRows", config.windows.maxRows)] where value != nil {
            warnings.append(ConfigIssue(.warning, "windows.\(name) does nothing from spec v24: windows.minCell sets the most columns and rows. It's dropped when the file is saved.",
                                        subject: name, rule: .retiredSetting))
        }
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

    /// A list's own rules (spec v18, Lists).
    private static func checkList(_ list: Config.List, at path: KeySequence, hasAction: Bool, held: Bool,
                                  _ error: (ConfigRule, String, String?) -> Void) {
        let subject = path.description
        if hasAction {
            error(.conflictingFields, "Entry “\(path)” has both an action and a list. Use one: an action runs, a list is a menu the app fills.", subject)
        }
        guard list.type == Config.List.recentWindows else {
            error(.unknownListType, "Entry “\(path)” has a list of type “\(list.type)”, which isn't one the app knows. Use \(Config.List.recentWindows).", subject)
            return
        }
        let counts = Config.List.countRange
        if !counts.contains(list.count) {
            error(.badListValue, "The list of “\(path)” has count \(list.count). Use a number from \(counts.lowerBound) to \(counts.upperBound).", subject)
        }
        if let spaces = list.spaces, !["all", "current"].contains(spaces) {
            error(.badListValue, "The list of “\(path)” has spaces “\(spaces)”. Use all or current.", subject)
        }
        if !["all", "display"].contains(list.scope) {
            error(.badListValue, "The list of “\(path)” has scope “\(list.scope)”. Use all or display.", subject)
        }
        if !Config.List.chooseValues.contains(list.choose) {
            error(.badListValue, "The list of “\(path)” has choose “\(list.choose)”. Use focus or swap.", subject)
        }
        // Swap only works with shown windows on the current Space (spec v19).
        let swapLeavesOut = [("minimized", list.minimized != nil), ("hidden", list.hidden != nil), ("spaces", list.spaces != nil)]
            .filter(\.1).map(\.0)
        if list.swaps, let field = swapLeavesOut.first {
            error(.conflictingFields, "The list of “\(path)” swaps, so “\(field)” doesn't go with it: Swap only works with windows shown on the current Space. Remove “\(field)”.", subject)
        }
        // The digits are the items' keys, so a held list can't be opened by one.
        let repeatKey = path.lastStep?.key ?? path.leader.key
        if held, repeatKey.isDigit {
            error(.stepIsRepeatKey, "The held list “\(path)” is opened by \(repeatKey.name), which is also one of its items' keys. Choose a key that isn't a digit.", subject)
        }
    }

    /// Builds the tree, keeping file order at every level.
    private static func tree(_ parsed: [(entry: Config.Entry, path: KeySequence)]) -> [BindingNode] {
        func node(_ item: (entry: Config.Entry, path: KeySequence)) -> BindingNode {
            let children = parsed.filter { $0.path.parent == item.path }.map(node)
            return BindingNode(path: item.path, title: item.entry.title, action: item.entry.action,
                               icon: item.entry.icon, hold: item.entry.hold, list: item.entry.list, children: children)
        }
        return parsed.filter { $0.path.isLeader }.map(node)
    }
}

/// Every error that stopped a config from loading, in file order.
public struct ConfigErrors: Error, Sendable, Equatable {
    public var issues: [ConfigIssue]
    public init(issues: [ConfigIssue]) { self.issues = issues }
}
