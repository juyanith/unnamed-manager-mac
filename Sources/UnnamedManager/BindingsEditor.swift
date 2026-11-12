import AppKit
import UnnamedManagerKit

/// The draft the Bindings window and Settings edit (M4). Every change is
/// one undoable step. A draft that validates is saved at once (S-033); one
/// with errors stays on screen with its errors and the file isn't touched.
@Observable
final class BindingsEditor {
    enum Field: Hashable { case key, title, icon, action }

    let store: ConfigStore
    /// What's on screen.
    private(set) var draft: ConfigDocument
    /// What's in the file. Equal to `draft` unless the draft has errors.
    private(set) var saved: ConfigDocument
    /// Errors in the draft that stop it being saved.
    private(set) var draftErrors: [ConfigIssue] = []
    /// The selected row in the outline, by path.
    var selection: KeySequence?
    /// The field to focus in the editor pane (S-024, S-034).
    var focus: Field?
    /// The row whose key is being recorded.
    var recording: KeySequence?
    /// New bindings that don't have an action yet (S-024).
    private(set) var needsAction: Set<KeySequence> = []

    /// Pauses the launcher while a key is recorded, so Hyper+Space records
    /// instead of opening the Guide.
    var onRecordingChange: ((Bool) -> Void)?

    init(store: ConfigStore) {
        self.store = store
        let document = store.document ?? ConfigDocument(config: Config(entries: []))
        draft = document
        saved = document
    }

    /// Every error to show above the outline: the file's own, then the draft's.
    var issues: [ConfigIssue] { store.errors + draftErrors }

    /// True when the draft has edits that couldn't be saved yet.
    var hasUnsavedEdits: Bool { draft != saved }

    // MARK: - Changes

    /// Makes one change as one undoable step named `name`, then saves if valid.
    func change(_ name: String, undo: UndoManager?, _ edit: (inout ConfigDocument) -> Void) {
        let before = (draft, needsAction, selection)
        edit(&draft)
        registerUndo(name, undo: undo, restoring: before)
        commit()
    }

    private func registerUndo(_ name: String, undo: UndoManager?,
                              restoring state: (ConfigDocument, Set<KeySequence>, KeySequence?)) {
        guard let undo else { return }
        undo.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                let current = (editor.draft, editor.needsAction, editor.selection)
                (editor.draft, editor.needsAction, editor.selection) = state
                editor.registerUndo(name, undo: undo, restoring: current)
                editor.commit()
            }
        }
        undo.setActionName(name)
    }

    /// Validates the draft and saves it when it's valid.
    private func commit() {
        needsAction = needsAction.filter { draft.entry($0)?.action == nil && draft.index(of: $0) != nil }
        var errors: [ConfigIssue] = needsAction.sorted { $0.description < $1.description }.map {
            ConfigIssue(.error, "Choose an action for “\($0)”.", subject: $0.description)
        }
        if case let .failure(failure) = draft.validate() {
            // A new binding without its action isn't an empty menu.
            errors += failure.issues.filter { issue in
                !needsAction.contains { issue.subject == $0.description && issue.message.contains("has no keys under it") }
            }
        }
        draftErrors = errors
        guard errors.isEmpty else { return }
        switch store.save(draft) {
        case .success: saved = draft
        case let .failure(failure): draftErrors = failure.issues
        }
    }

    /// Takes the file's version when it changed on disk (S-033). Edits that
    /// couldn't be saved yet are replaced, since the file is the source of truth.
    func reloadFromStore() {
        guard let document = store.document, document != saved else { return }
        draft = document
        saved = document
        draftErrors = []
        needsAction = []
        if let selection, draft.index(of: selection) == nil { self.selection = nil }
    }

    // MARK: - Commands

    /// The menu new entries go into: the selected menu, or a selected binding's menu.
    var targetMenu: KeySequence? {
        guard let selection else { return draft.children(of: nil).first }
        return draft.entry(selection)?.action == nil && !needsAction.contains(selection) ? selection : selection.parent
    }

    /// New Binding (⌘N): at the end of the target menu, with its key recorder
    /// on, or a direct binding with nothing selected.
    func addBinding(undo: UndoManager?) {
        let parent = selection == nil ? nil : targetMenu
        var added: KeySequence?
        change("New Binding", undo: undo) { added = $0.addEntry(under: parent, title: "New Binding", action: nil) }
        if let added {
            needsAction.insert(added)
            commit()
            select(added, focus: .key)
        }
    }

    /// New Menu (⇧⌘N): a menu in the target menu, or a new leader with nothing selected.
    func addMenu(undo: UndoManager?) {
        let parent = selection == nil ? nil : targetMenu
        var added: KeySequence?
        change("New Menu", undo: undo) { added = $0.addEntry(under: parent, title: "New Menu", action: nil) }
        if let added { select(added, focus: .key) }
    }

    func select(_ path: KeySequence, focus field: Field?) {
        selection = path
        focus = field
        if field == .key { startRecording(path) } else if recording != nil { stopRecording() }
    }

    func setTitle(_ path: KeySequence, _ title: String, undo: UndoManager?) {
        guard draft.entry(path)?.title != title else { return }
        change("Rename", undo: undo) { $0.setTitle(path, title) }
    }

    /// Sets or clears an entry's own icon (S-056).
    func setIcon(_ path: KeySequence, _ icon: String, undo: UndoManager?) {
        let trimmed = icon.trimmingCharacters(in: .whitespaces)
        guard (draft.entry(path)?.icon ?? "") != trimmed else { return }
        change("Change Icon", undo: undo) { $0.setIcon(path, trimmed) }
    }

    /// Why an icon won't show, or nil when it will (or there's none).
    static func iconProblem(_ icon: String) -> String? {
        let trimmed = icon.trimmingCharacters(in: .whitespaces)
        switch trimmed.isEmpty ? nil : IconSource(trimmed) {
        case let .symbol(name) where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil:
            return "No SF Symbol named “\(name)”."
        case let .file(path) where !FileManager.default.fileExists(atPath: path):
            return "No file at \(trimmed)."
        default:
            return nil
        }
    }

    /// The Icon field's menu: symbols that fit common bindings.
    static let commonSymbols = ["terminal", "folder", "doc.text", "globe", "envelope", "calendar", "music.note",
                                "camera", "photo", "gearshape", "star", "bolt", "keyboard", "magnifyingglass",
                                "hammer", "house"]

    func setAction(_ path: KeySequence, _ action: String, undo: UndoManager?) {
        change("Change Action", undo: undo) { $0.setAction(path, action) }
    }

    /// New Action… from a binding's action popup: a Do Nothing action to fill in.
    func newAction(for path: KeySequence, undo: UndoManager?) -> String {
        let id = draft.freeActionID()
        change("New Action", undo: undo) {
            $0.setAction(id: id, .noop)
            $0.setAction(path, id)
        }
        return id
    }

    /// Why `key` can't be used for the row, in words, or nil.
    func keyProblem(_ path: KeySequence, _ key: Chord) -> String? {
        if !path.isLeader && !key.modifiers.isEmpty {
            return "Keys inside a menu can't use modifiers. Only the leader can."
        }
        switch draft.keyProblem(for: path, newKey: key) {
        case let .keyTaken(other): return "\(key) is already used by “\(draft.entry(KeySequence(parsing: other)!)?.title ?? other)”."
        case let .reservedKey(name): return "\(name) is the \(name == draft.config.runtime.cancelKey ? "cancel" : "back") key."
        case let .keptByMacOS(chord): return "macOS keeps \(chord) for its diagnostics, so Unnamed Manager never sees it."
        default: return nil
        }
    }

    /// Sets a row's key. Returns the problem instead when the key can't be used.
    func setKey(_ path: KeySequence, _ key: Chord, undo: UndoManager?) -> String? {
        if let problem = keyProblem(path, key) { return problem }
        var renamed = path
        change("Change Key", undo: undo) { document in
            if let new = try? document.changeKey(of: path, to: key) { renamed = new }
        }
        needsAction = Set(needsAction.map { $0 == path ? renamed : $0 })
        commit()
        selection = renamed
        return nil
    }

    func duplicate(_ path: KeySequence, undo: UndoManager?) {
        var copy: KeySequence?
        change("Duplicate", undo: undo) { copy = $0.duplicateEntry(path) }
        if let copy { selection = copy }
    }

    func delete(_ path: KeySequence, undo: UndoManager?) {
        let next = draft.children(of: path.parent).drop { $0 != path }.dropFirst().first ?? path.parent
        change("Delete", undo: undo) { $0.removeEntry(path) }
        selection = next
    }

    /// How many entries under a menu (for the delete confirmation).
    func descendantCount(_ path: KeySequence) -> Int {
        draft.paths.compactMap { $0 }.filter { $0.isDescendant(of: path) }.count
    }

    func move(in parent: KeySequence?, from source: IndexSet, to destination: Int, undo: UndoManager?) {
        change("Move", undo: undo) { $0.moveChildren(of: parent, from: source, to: destination) }
    }

    func sort(_ menu: KeySequence?, undo: UndoManager?) {
        change("Sort Alphabetically", undo: undo) { $0.sortChildren(of: menu) }
    }

    /// Any other change, such as an action, a context or a setting.
    func edit(_ name: String, undo: UndoManager?, _ edit: (inout ConfigDocument) -> Void) {
        change(name, undo: undo, edit)
    }

    /// Shows a document without saving it, for snapshots of empty pages (S-042).
    func preview(_ document: ConfigDocument) {
        draft = document
        selection = nil
    }

    /// Puts back what's in the file after a preview.
    func endPreview() {
        draft = saved
    }

    /// What VoiceOver reads for a row: "key, title, action" (S-044).
    func accessibilityLabel(for path: KeySequence) -> String {
        let entry = draft.entry(path)
        let key = (path.lastStep ?? path.leader).description
        let action = entry?.action ?? (needsAction.contains(path) ? "no action yet" : "menu")
        return "\(key), \(entry?.title ?? ""), \(action)"
    }

    // MARK: - Recording

    func startRecording(_ path: KeySequence) {
        recording = path
        onRecordingChange?(true)
    }

    func stopRecording() {
        recording = nil
        if focus == .key { focus = nil }
        onRecordingChange?(false)
    }
}
