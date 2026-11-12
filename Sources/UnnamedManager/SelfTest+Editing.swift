import AppKit
import OSLog
import Synchronization
import UnnamedManagerKit

/// Self-test checks for M4: editing in the Bindings window and Settings.
extension SelfTest {
    /// M4: the Bindings window's editing, through the same editor the pages use.
    static func editorChecks(_ model: AppModel) async {
        let editor = model.editor
        let store = model.store
        editor.reloadFromStore()
        let undo = UndoManager()
        undo.groupsByEvent = false
        func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }
        func fileLines() -> [String] {
            ((try? String(contentsOf: store.url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        let commands = KeySequence(parsing: "Hyper+Space")!

        // S-024: New Binding goes at the end of the selected menu, recorder on, unsaved until it has an action.
        editor.selection = commands
        let before = fileLines()
        step { editor.addBinding(undo: undo) }
        let added = editor.selection
        check("S-024 a new binding goes at the end of the selected menu",
              added != nil && editor.draft.children(of: commands).last == added, "\(String(describing: added))")
        check("S-024 the new binding's key recorder is on", editor.recording == added && editor.focus == .key)
        check("S-024 a binding without an action isn't saved, and says why",
              fileLines() == before && editor.draftErrors.first?.message.hasPrefix("Choose an action") == true)
        editor.stopRecording()

        // S-025: keys are checked and stored in canonical form.
        if let added {
            check("S-025 a key that's taken in the menu is refused",
                  editor.setKey(added, Chord(key: .f), undo: undo)?.contains("already used") == true)
            check("S-025 a key inside a menu can't have modifiers",
                  editor.setKey(added, Chord(modifiers: .command, key: .k), undo: undo) != nil)
            check("S-025 the cancel key is refused", editor.setKey(added, Chord(key: .escape), undo: undo)?.contains("cancel key") == true)
            var problem: String?
            step { problem = editor.setKey(added, Chord(parsing: "k")!, undo: undo) }
            let renamed = KeySequence(parsing: "Hyper+Space K")!
            check("S-025 a recorded key is stored in canonical form", problem == nil && editor.selection == renamed
                  && editor.draft.entry(renamed) != nil)

            // S-026: choosing an action saves it, changing only that line.
            check("S-026 the action popup lists every action and New Action…",
                  editor.actionChoices == editor.draft.sortedActionIDs + [BindingsEditor.newActionTag])
            // S-045: lists are alphabetical even where the file isn't. A new
            // action goes at the end of the file but sorts first in the list.
            var later = editor.draft
            later.setAction(id: "a-first", .noop)
            check("S-045 actions are listed alphabetically, not in file order",
                  later.actionOrder.last == "a-first" && later.sortedActionIDs.first == "a-first"
                  && later.sortedActionIDs == later.actionOrder.sorted { $0.compare($1, options: [.caseInsensitive, .numeric]) == .orderedAscending })
            step { editor.setAction(renamed, "open-finder", undo: undo) }
            let withBinding = fileLines()
            check("S-026 a binding with its action is saved", editor.draftErrors.isEmpty
                  && withBinding.contains { $0.contains(#""keys": "Hyper+Space K""#) })
            step { editor.setTitle(renamed, "Finder Again", undo: undo) }
            let retitled = fileLines()
            check("S-026 changing the title rewrites only that entry",
                  retitled.count == withBinding.count && zip(retitled, withBinding).filter { $0 != $1 }.count == 1)

            // S-056: an icon of your own is written, wins over the action's, and undoes.
            step { editor.setIcon(renamed, "star", undo: undo) }
            let starred = store.loaded.flatMap { config in
                config.leaders[0].child(for: renamed.lastStep!.key).map { config.iconSource($0) } }
            check("S-056 setting an icon writes it and it wins over the action's icon",
                  fileLines().contains { $0.contains(#""icon": "star""#) } && starred == .symbol("star"), "\(String(describing: starred))")
            undo.undo()
            check("S-056 Undo restores the entry without an icon",
                  editor.draft.entry(renamed)?.icon == nil && !fileLines().contains { $0.contains(#""icon""#) })
            step { editor.setIcon(renamed, "star", undo: undo) }
            step { editor.setIcon(renamed, "", undo: undo) }
            check("S-056 clearing the icon leaves it out of the file", !fileLines().contains { $0.contains(#""icon""#) })
            check("S-056 an unknown SF Symbol is named in the editor",
                  BindingsEditor.iconProblem("no-such-symbol") == "No SF Symbol named “no-such-symbol”."
                  && BindingsEditor.iconProblem("terminal") == nil && BindingsEditor.iconProblem("") == nil)
            let icons = GuideIcons()
            icons.load([.symbol("no-such-symbol"), .symbol("terminal")])
            check("S-056 an unknown SF Symbol shows no icon in the Guide",
                  icons.icon(for: .symbol("no-such-symbol")) == nil && icons.icon(for: .symbol("terminal")) != nil)

            // S-028: reordering is saved, stays in its menu, and the Guide follows.
            step { editor.move(in: commands, from: [2], to: 0, undo: undo) }
            let order = editor.draft.children(of: commands).map { $0.lastStep!.key.name }
            let guide = store.loaded.map { GuideContent(menu: $0.leaders[0], path: ["Commands"], config: $0, frontApp: nil) }
            check("S-028 a new order is written and the Guide lists it", order == ["K", "F", "T"]
                  && guide?.rows.map(\.key) == ["K", "F", "T"], "\(order)")
            var moved = editor.draft
            let unchanged = moved
            moved.moveEntry(renamed, before: KeySequence(parsing: "Ctrl+W 1")!)
            check("S-028 an item can't be dropped into a different menu", moved == unchanged)

            // S-029: Sort Alphabetically, and undo.
            step { editor.sort(commands, undo: undo) }
            check("S-029 sorting puts the menu in order", editor.draft.children(of: commands).map { $0.lastStep!.key.name } == ["F", "K", "T"])
            undo.undo()
            check("S-029 Sort Alphabetically can be undone", editor.draft.children(of: commands).map { $0.lastStep!.key.name } == ["K", "F", "T"])

            // S-027: deleting a menu with entries counts them, and undo brings them back.
            let apps = editor.draft.config.entries.count
            step { editor.addMenu(undo: undo) }
            if let menu = editor.selection {
                editor.stopRecording()
                step { editor.selection = menu; editor.addBinding(undo: undo) }
                if let child = editor.selection { step { editor.setAction(child, "open-terminal", undo: undo) } }
                editor.stopRecording()
                check("S-027 a menu's entries are counted before deleting", editor.descendantCount(menu) == 1)
                step { editor.delete(menu, undo: undo) }
                check("S-027 deleting removes the menu and what's under it", editor.draft.config.entries.count == apps)
                undo.undo()
                check("S-027 ⌘Z restores them", editor.draft.index(of: menu) != nil && editor.descendantCount(menu) == 1)
            }
        }

        // S-030: renaming an action updates bindings; deleting one in use is blocked.
        step { editor.edit("Rename Action", undo: undo) { try? $0.renameAction("open-finder", to: "finder") } }
        check("S-030 renaming an action updates every binding", editor.draft.users(of: "finder").count >= 2
              && editor.draft.config.actions["open-finder"] == nil && fileLines().contains { $0.contains(#""action": "finder""#) })
        var blocked = editor.draft
        do throws(ConfigDocument.EditError) {
            try blocked.removeAction("finder")
            check("S-030 deleting an action in use is blocked", false)
        } catch {
            check("S-030 deleting an action in use is blocked and lists its users", {
                if case let .inUse(users) = error { return users.contains("Hyper+Space F") } else { return false }
            }())
        }
        check("S-030 an app's bundle id comes from its bundle", Bundle(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"))?.bundleIdentifier == "com.apple.calculator")

        // S-031: contexts reorder, and the order is saved.
        step { editor.edit("Contexts", undo: undo) { $0.config.contexts = [.init(id: "one", apps: []), .init(id: "two", apps: [])] } }
        step { editor.edit("Move Context", undo: undo) { $0.moveContexts(from: [1], to: 0) } }
        check("S-031 a new context order is saved", store.document?.config.contexts.map(\.id) == ["two", "one"])

        // S-032: settings are saved like any other edit.
        step { editor.edit("Change Delay", undo: undo) { $0.config.runtime.hudDelayMs = SettingsValues.milliseconds(-100) } }
        check("S-032 a negative delay becomes 0", store.loaded?.config.runtime.hudDelayMs == 0)
        step { editor.edit("Change Delay", undo: undo) { $0.config.runtime.hudDelayMs = 400 } }
        check("S-032 a setting is written to the file", fileLines().contains { $0.contains(#""hudDelayMs": 400"#) })

        // S-034: clicking an error selects the row and the field it's about.
        step { editor.addBinding(undo: undo) }
        if let issue = editor.draftErrors.first {
            editor.stopRecording()
            editor.selection = nil
            editor.show(issue)
            check("S-034 clicking an error selects its row and focuses the field",
                  editor.selection?.description == issue.subject && editor.focus == .action, issue.message)
        }

        // S-048: with nothing selected, New Binding adds a direct binding, which runs from its chord.
        undo.undo()
        editor.selection = nil
        step { editor.addBinding(undo: undo) }
        let direct = editor.selection
        check("S-048 New Binding with nothing selected adds a direct binding",
              direct?.isLeader == true && editor.recording == direct, "\(String(describing: direct))")
        editor.stopRecording()
        let plain = editor.draft.sortedActionIDs.first { id in
            if case .contextual = editor.draft.config.actions[id] { false } else { true }
        }
        if let direct, let plain {
            step { editor.setAction(direct, plain, undo: undo) }
            let node = store.loaded?.leaders.first { $0.path == direct }
            check("S-048 a direct binding with an action is saved", node?.action == plain && fileLines().contains { $0.contains(direct.description) })
            var ran = false
            if let loaded = store.loaded, let code = direct.leader.key.keyCode {
                var engine = SequenceEngine(config: loaded)
                let output = engine.handle(.down(keyCode: code, modifiers: direct.leader.modifiers, isRepeat: false))
                if case let .run(binding, _) = output.effect { ran = output.consume && binding.path == direct && !engine.isActive }
            }
            check("S-048 its chord runs the action at once, with no sequence", ran)
            // A chord recorded with ⌃⌥⇧ or ⌃⌥⌘ is saved as Meh or CAG.
            var named = direct
            for (modifiers, name) in [(Modifiers.meh, "Meh+"), (Modifiers.cag, "CAG+")] {
                var problem: String?
                step { problem = editor.setKey(named, Chord(modifiers: modifiers, key: .f19), undo: undo) }
                named = editor.selection ?? named
                check("S-025 a chord with \(name.dropLast()) modifiers is saved as \(name)F19",
                      problem == nil && fileLines().contains { $0.contains("\"\(name)F19\"") }, problem ?? named.description)
            }
            step { editor.delete(named, undo: undo) }
            check("S-048 deleting it leaves the file without it", !fileLines().contains { $0.contains(named.description) })
        } else {
            check("S-048 a direct binding can be added", false)
        }
    }
}
