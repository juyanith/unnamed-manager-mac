import SwiftUI
import UnnamedManagerKit

/// The commands on a row in the outline (S-043). The right-click menu and
/// the menu bar are both built from this list, so their names and
/// shortcuts always match. Context menus don't show shortcuts (HIG); the
/// menu bar does.
enum OutlineCommand: String, CaseIterable, Identifiable {
    case newBinding, newMenu, recordKey, duplicate, sortAlphabetically, delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newBinding: "New Binding"
        case .newMenu: "New Menu"
        case .recordKey: "Record Key"
        case .duplicate: "Duplicate"
        case .sortAlphabetically: "Sort Alphabetically"
        case .delete: "Delete"
        }
    }

    /// The menu bar shortcut. Delete is ⌫ through the system's Edit > Delete.
    var shortcut: KeyboardShortcut? {
        switch self {
        case .newBinding: KeyboardShortcut("n")
        case .newMenu: KeyboardShortcut("n", modifiers: [.command, .shift])
        case .recordKey: KeyboardShortcut("k")
        case .duplicate: KeyboardShortcut("d")
        case .sortAlphabetically, .delete: nil
        }
    }

    /// Which commands a row's right-click menu offers: menus get the ones
    /// that add or sort inside them.
    static func forRow(isMenu: Bool) -> [OutlineCommand] {
        isMenu ? [.newBinding, .newMenu, .recordKey, .duplicate, .sortAlphabetically, .delete]
               : [.recordKey, .duplicate, .delete]
    }

    /// Where each command sits in the menu bar. Delete is the system's
    /// Edit > Delete (⌫), from the outline's onDeleteCommand.
    static let menuBarFile: [OutlineCommand] = [.newBinding, .newMenu]
    static let menuBarEdit: [OutlineCommand] = [.recordKey, .duplicate, .sortAlphabetically]

    /// Every command the menu bar has, with Delete from the system.
    static var inMenuBar: [OutlineCommand] { menuBarFile + menuBarEdit + [.delete] }

    /// Runs the command on `path`, or on the selection.
    @MainActor
    func perform(on path: KeySequence?, editor: BindingsEditor, undo: UndoManager?, requestDelete: (KeySequence) -> Void) {
        switch self {
        case .newBinding:
            if let path { editor.selection = path }
            editor.addBinding(undo: undo)
        case .newMenu:
            if let path { editor.selection = path }
            editor.addMenu(undo: undo)
        case .recordKey:
            if let path = path ?? editor.selection { editor.select(path, focus: .key) }
        case .duplicate:
            if let path = path ?? editor.selection { editor.duplicate(path, undo: undo) }
        case .sortAlphabetically:
            editor.sort(path ?? editor.targetMenu, undo: undo)
        case .delete:
            if let path = path ?? editor.selection { requestDelete(path) }
        }
    }
}
