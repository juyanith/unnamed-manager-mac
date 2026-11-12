import SwiftUI
import UnnamedManagerKit

/// The editor beside the outline: the selected row's key, title and action
/// (S-024 to S-026).
struct EntryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @FocusState private var focus: BindingsEditor.Field?
    @State private var title = ""
    @State private var icon = ""

    private var editor: BindingsEditor { model.editor }

    var body: some View {
        if let path = editor.selection, let entry = editor.draft.entry(path) {
            Form {
                Section {
                    LabeledContent("Key") { KeyRecorder(path: path) }
                    TextField("Title", text: $title)
                        .focused($focus, equals: .title)
                        .onSubmit { editor.setTitle(path, title, undo: undo) }
                        .onChange(of: focus) { old, _ in
                            if old == .title { editor.setTitle(path, title, undo: undo) }
                        }
                        .textEntry("Title")
                } footer: {
                    Text(footer(path, isBinding: entry.action != nil || editor.needsAction.contains(path)))
                }
                iconSection(path)
                if entry.action != nil || editor.needsAction.contains(path) {
                    Section {
                        actionPicker(path, entry)
                    } footer: {
                        Text("What this binding does. Edit actions on the Actions page.")
                    }
                } else {
                    Section {
                        LabeledContent("Kind", value: path.isLeader ? "Leader" : "Menu")
                        LabeledContent("Keys under it", value: "\(editor.draft.children(of: path).count)")
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { title = entry.title; icon = entry.icon ?? "" }
            .onChange(of: path) { _, _ in
                title = editor.draft.entry(path)?.title ?? ""
                icon = editor.draft.entry(path)?.icon ?? ""
            }
            .onChange(of: editor.focus, initial: true) { _, field in
                if field == .title || field == .action { focus = field }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "keyboard",
                                   description: Text("Select a binding or menu to edit it."))
        }
    }

    /// Icon (S-056): a symbol name or a file path, a preview, and common symbols.
    private func iconSection(_ path: KeySequence) -> some View {
        Section {
            LabeledContent("Icon") {
                HStack(spacing: Space.sm) {
                    // Left-aligned like textEntry, which would add a second label here.
                    TextField("Icon", text: $icon, prompt: Text("Automatic"))
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .focused($focus, equals: .icon)
                        .onSubmit { editor.setIcon(path, icon, undo: undo) }
                        .onChange(of: focus) { old, _ in
                            if old == .icon { editor.setIcon(path, icon, undo: undo) }
                        }
                    let trimmed = icon.trimmingCharacters(in: .whitespaces)
                    // VoiceOver reads a symbol's name, or a file's name without its folder.
                    EntryIcon(source: trimmed.isEmpty ? nil : IconSource(trimmed), looksUp: true,
                              accessibilityName: (trimmed as NSString).lastPathComponent)
                    Menu {
                        ForEach(BindingsEditor.commonSymbols, id: \.self) { name in
                            Button { choose(name, path) } label: { Label(name, systemImage: name) }
                        }
                        Divider()
                        Button("Automatic") { choose("", path) }
                    } label: {
                        Label("Common Symbols", systemImage: "square.grid.2x2")
                    }
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choose a common SF Symbol")
                }
            }
        } footer: {
            Text(BindingsEditor.iconProblem(icon)
                 ?? "An SF Symbol name, such as terminal, or the path of a file whose icon to use. When this is empty, menus show the app's keycaps, and apps and Open targets their own icon.")
        }
    }

    private func choose(_ name: String, _ path: KeySequence) {
        icon = name
        editor.setIcon(path, name, undo: undo)
    }

    private func footer(_ path: KeySequence, isBinding: Bool) -> String {
        guard path.isLeader else { return "A single key, pressed after the keys above it." }
        return isBinding ? "A direct binding is a chord that runs its action from anywhere, with no menu."
                         : "A leader is a chord that opens its menu from anywhere."
    }

    private func actionPicker(_ path: KeySequence, _ entry: Config.Entry) -> some View {
        let document = editor.draft
        let ids = document.sortedActionIDs
        return Picker("Action", selection: Binding(
            get: { entry.action ?? "" },
            set: { id in
                if id == BindingsEditor.newActionTag {
                    let created = editor.newAction(for: path, undo: undo)
                    model.showAction(created)
                } else if !id.isEmpty {
                    editor.setAction(path, id, undo: undo)
                }
            })) {
            if entry.action == nil { Text("Choose an Action").tag("") }
            ForEach(ids, id: \.self) { id in
                Text("\(id) (\(document.config.actions[id]!.displayName))").tag(id)
            }
            Divider()
            Text("New Action…").tag(BindingsEditor.newActionTag)
        }
        .focused($focus, equals: .action)
    }
}

extension BindingsEditor {
    /// The popup tag for "New Action…", which no action id can be.
    static let newActionTag = "\u{0}new"

    /// The action popup's choices: every action in alphabetical order (S-045), then New Action… (S-026).
    var actionChoices: [String] {
        draft.sortedActionIDs + [Self.newActionTag]
    }
}

