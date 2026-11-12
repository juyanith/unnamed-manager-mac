import Foundation

/// A config being edited (M4). Every edit changes the flat entry list as
/// little as it can, so entries you didn't touch keep their place in the
/// file. `data()` writes it with ConfigWriter.
public struct ConfigDocument: Sendable, Equatable {
    public var config: Config
    /// The order the `actions` object was written in.
    public var actionOrder: [String]

    public init(config: Config, actionOrder: [String] = []) {
        self.config = config
        self.actionOrder = ConfigWriter.ordered(Array(config.actions.keys), by: actionOrder)
    }

    /// Reads a file's text. Throws the decoding error; validation is separate.
    public init(data: Data) throws {
        let config = try JSONDecoder().decode(Config.self, from: data)
        self.init(config: config, actionOrder: JSONKeyOrder.keys(ofTopLevelObject: "actions", in: data))
    }

    /// Every action id in alphabetical order, for lists (S-045): case doesn't
    /// matter and numbers sort by value, so "open-2" comes before "open-10".
    /// The file keeps `actionOrder`.
    public var sortedActionIDs: [String] {
        config.actions.keys.sorted(by: Self.alphabetical)
    }

    static func alphabetical(_ a: String, _ b: String) -> Bool {
        switch a.compare(b, options: [.caseInsensitive, .numeric]) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: a < b
        }
    }

    public func data() -> Data {
        Data(ConfigWriter.write(config, actionOrder: actionOrder).utf8)
    }

    /// Validates the document as it would be written.
    public func validate() -> Result<LoadedConfig, ConfigErrors> {
        ConfigValidator.validate(config)
    }

    // MARK: - Reading the tree

    /// Each entry's parsed path, or nil for keys that don't parse.
    public var paths: [KeySequence?] { config.entries.map { KeySequence(parsing: $0.keys) } }

    public func index(of path: KeySequence) -> Int? {
        config.entries.firstIndex { KeySequence(parsing: $0.keys) == path }
    }

    public func entry(_ path: KeySequence) -> Config.Entry? {
        index(of: path).map { config.entries[$0] }
    }

    /// The direct children of a menu, or the leaders for nil, in file order.
    public func children(of parent: KeySequence?) -> [KeySequence] {
        paths.compactMap { $0 }.filter { $0.parent == parent }
    }

    /// Indexes of an entry and everything under it, in file order.
    func subtreeIndexes(_ path: KeySequence) -> [Int] {
        paths.indices.filter { i in paths[i].map { $0 == path || $0.isDescendant(of: path) } ?? false }
    }

    /// Bindings that use an action, in file order.
    public func users(of actionID: String) -> [KeySequence] {
        config.entries.compactMap { $0.action == actionID ? KeySequence(parsing: $0.keys) : nil }
    }

    // MARK: - Entries

    public enum EditError: Error, Sendable, Equatable {
        case keyTaken(String)
        case reservedKey(String)
        case keptByMacOS(String)
        case notFound
        case idTaken(String)
        case inUse([String])
    }

    /// Adds a menu (action nil) or a binding at the end of `parent`'s
    /// children, or a new leader for nil, with the first free key. Returns
    /// its path.
    @discardableResult
    public mutating func addEntry(under parent: KeySequence?, title: String, action: String?) -> KeySequence {
        let path = freePath(under: parent)
        let entry = Config.Entry(keys: path.description, title: title, action: action)
        if let parent, let last = subtreeIndexes(parent).last {
            config.entries.insert(entry, at: last + 1)
        } else {
            config.entries.append(entry)
        }
        return path
    }

    /// The first key not taken among siblings: A–Z, then 0–9. Leaders get Hyper+letter.
    func freePath(under parent: KeySequence?) -> KeySequence {
        let taken = Set(children(of: parent).map { $0.lastStep?.key ?? $0.leader.key })
        let reserved: Set<KeyName> = parent == nil ? [] : reservedKeys
        let candidates: [KeyName] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t,
                                     .u, .v, .w, .x, .y, .z, .d1, .d2, .d3, .d4, .d5, .d6, .d7, .d8, .d9, .d0]
        let key = candidates.first { !taken.contains($0) && !reserved.contains($0) } ?? .f13
        guard let parent else { return KeySequence(leader: Chord(modifiers: .hyper, key: key)) }
        return KeySequence(leader: parent.leader, steps: parent.steps + [Chord(key: key)])
    }

    var reservedKeys: Set<KeyName> {
        Set([KeyName(parsing: config.runtime.cancelKey), KeyName(parsing: config.runtime.backKey)].compactMap { $0 })
    }

    /// Removes an entry and everything under it. Returns how many entries went.
    @discardableResult
    public mutating func removeEntry(_ path: KeySequence) -> Int {
        let indexes = subtreeIndexes(path)
        for i in indexes.reversed() { config.entries.remove(at: i) }
        return indexes.count
    }

    /// Copies an entry and everything under it to the first free key in the
    /// same menu, right after the original, titled "… Copy". Returns the copy's path.
    @discardableResult
    public mutating func duplicateEntry(_ path: KeySequence) -> KeySequence? {
        let block = subtreeIndexes(path)
        guard let last = block.last, let original = entry(path) else { return nil }
        let copy = freePath(under: path.parent)
        var entries: [Config.Entry] = []
        for i in block {
            guard let old = KeySequence(parsing: config.entries[i].keys) else { continue }
            var duplicated = config.entries[i]
            duplicated.keys = old.replacingPrefix(path, with: copy).description
            if old == path { duplicated.title = original.title + " Copy" }
            entries.append(duplicated)
        }
        config.entries.insert(contentsOf: entries, at: last + 1)
        return copy
    }

    public mutating func setTitle(_ path: KeySequence, _ title: String) {
        guard let i = index(of: path) else { return }
        config.entries[i].title = title
    }

    /// An empty or blank icon is left out of the file (S-056).
    public mutating func setIcon(_ path: KeySequence, _ icon: String?) {
        guard let i = index(of: path) else { return }
        let trimmed = icon?.trimmingCharacters(in: .whitespaces) ?? ""
        config.entries[i].icon = trimmed.isEmpty ? nil : trimmed
    }

    public mutating func setAction(_ path: KeySequence, _ action: String?) {
        guard let i = index(of: path) else { return }
        config.entries[i].action = action
    }

    /// Why `key` can't be this entry's key, or nil when it can.
    public func keyProblem(for path: KeySequence, newKey: Chord) -> EditError? {
        let parent = path.parent
        if parent == nil, newKey.isKeptByMacOS {
            return .keptByMacOS(newKey.description)
        }
        if parent != nil {
            if reservedKeys.contains(newKey.key) && newKey.modifiers.isEmpty {
                return .reservedKey(newKey.key.name)
            }
        }
        let renamed = path.replacingLast(with: newKey)
        if renamed != path, children(of: parent).contains(renamed) {
            return .keyTaken(renamed.description)
        }
        return nil
    }

    /// Changes an entry's own key (the last step, or the leader chord), and
    /// every path under it. Returns the new path.
    @discardableResult
    public mutating func changeKey(of path: KeySequence, to newKey: Chord) throws(EditError) -> KeySequence {
        if let problem = keyProblem(for: path, newKey: newKey) { throw problem }
        let renamed = path.replacingLast(with: newKey)
        for i in subtreeIndexes(path) {
            guard let old = KeySequence(parsing: config.entries[i].keys) else { continue }
            config.entries[i].keys = old.replacingPrefix(path, with: renamed).description
        }
        return renamed
    }

    /// Moves an entry, with everything under it, before `sibling` in the
    /// same menu, or to the end of the menu for nil. Entries never change menu.
    public mutating func moveEntry(_ path: KeySequence, before sibling: KeySequence?) {
        guard sibling != path, sibling == nil || sibling?.parent == path.parent else { return }
        let block = subtreeIndexes(path)
        guard !block.isEmpty else { return }
        let moving = block.map { config.entries[$0] }
        for i in block.reversed() { config.entries.remove(at: i) }
        let insertAt: Int
        if let sibling, let target = index(of: sibling) {
            insertAt = target
        } else if let parent = path.parent, let last = subtreeIndexes(parent).last {
            insertAt = last + 1
        } else {
            insertAt = config.entries.count
        }
        config.entries.insert(contentsOf: moving, at: insertAt)
    }

    /// Moves children of a menu by offsets, the way a list's onMove reports it.
    public mutating func moveChildren(of parent: KeySequence?, from source: IndexSet, to destination: Int) {
        let order = children(of: parent)
        let moving = source.sorted().map { order[$0] }
        var final = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        final.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        reorderChildren(final)
    }

    /// Puts a menu's children in this order by moving each to the end.
    private mutating func reorderChildren(_ order: [KeySequence]) {
        for path in order { moveEntry(path, before: nil) }
    }

    /// Sorts a menu's children (S-029): named keys alphabetically with
    /// F-keys by number, then digits, then letters.
    public mutating func sortChildren(of parent: KeySequence?) {
        let sorted = children(of: parent).sorted { a, b in
            Self.sortsBefore(a.lastStep?.key ?? a.leader.key, b.lastStep?.key ?? b.leader.key)
        }
        reorderChildren(sorted)
    }

    public static func sortsBefore(_ a: KeyName, _ b: KeyName) -> Bool {
        func group(_ key: KeyName) -> Int {
            let name = key.name
            if name.count == 1, name.first!.isNumber { return 1 }
            if name.count == 1, name.first!.isLetter { return 2 }
            return 0
        }
        if group(a) != group(b) { return group(a) < group(b) }
        return a.name.compare(b.name, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    // MARK: - Actions

    public mutating func setAction(id: String, _ action: Config.Action) {
        if config.actions[id] == nil { actionOrder.append(id) }
        config.actions[id] = action
    }

    /// A new id like "new-action", "new-action-2".
    public func freeActionID(_ base: String = "new-action") -> String {
        var id = base
        var n = 2
        while config.actions[id] != nil { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    /// Renames an action and every binding that uses it.
    public mutating func renameAction(_ id: String, to newID: String) throws(EditError) {
        guard id != newID else { return }
        guard let action = config.actions[id] else { throw .notFound }
        guard config.actions[newID] == nil else { throw .idTaken(newID) }
        config.actions[id] = nil
        config.actions[newID] = action
        actionOrder = actionOrder.map { $0 == id ? newID : $0 }
        for i in config.entries.indices where config.entries[i].action == id {
            config.entries[i].action = newID
        }
    }

    /// Deletes an action no binding uses. Throws the users otherwise.
    public mutating func removeAction(_ id: String) throws(EditError) {
        let users = users(of: id)
        guard users.isEmpty else { throw .inUse(users.map(\.description)) }
        config.actions[id] = nil
        actionOrder.removeAll { $0 == id }
    }

    // MARK: - Contexts

    public mutating func moveContexts(from source: IndexSet, to destination: Int) {
        let moving = source.map { config.contexts[$0] }
        let before = destination < config.contexts.count ? config.contexts[destination].id : nil
        config.contexts.removeAll { c in moving.contains { $0.id == c.id } }
        let at = before.flatMap { b in config.contexts.firstIndex { $0.id == b } } ?? config.contexts.count
        config.contexts.insert(contentsOf: moving, at: at)
    }

    /// Renames a context and the variants that name it.
    public mutating func renameContext(_ id: String, to newID: String) throws(EditError) {
        guard id != newID else { return }
        guard config.contexts.contains(where: { $0.id == id }) else { throw .notFound }
        guard !config.contexts.contains(where: { $0.id == newID }) else { throw .idTaken(newID) }
        for i in config.contexts.indices where config.contexts[i].id == id { config.contexts[i].id = newID }
        for (actionID, action) in config.actions {
            guard case .contextual(var variants, let fallback) = action, let variant = variants[id] else { continue }
            variants[id] = nil
            variants[newID] = variant
            config.actions[actionID] = .contextual(variants: variants, fallback: fallback)
        }
    }
}

extension KeySequence {
    /// True when this path is under `ancestor`, at any depth.
    public func isDescendant(of ancestor: KeySequence) -> Bool {
        leader == ancestor.leader && steps.count > ancestor.steps.count
            && Array(steps.prefix(ancestor.steps.count)) == ancestor.steps
    }

    /// This path with its own key (last step, or the leader) replaced.
    public func replacingLast(with key: Chord) -> KeySequence {
        isLeader ? KeySequence(leader: key) : KeySequence(leader: leader, steps: steps.dropLast() + [key])
    }

    /// This path with `old` at its start replaced by `new`.
    func replacingPrefix(_ old: KeySequence, with new: KeySequence) -> KeySequence {
        guard self == old || isDescendant(of: old) else { return self }
        return KeySequence(leader: new.leader, steps: new.steps + steps.dropFirst(old.steps.count))
    }
}
