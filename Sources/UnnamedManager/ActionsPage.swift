import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UnnamedManagerKit

/// The Actions page (S-030): every action with its type and how many
/// bindings use it, and a form for the selected one that changes with its type.
struct ActionsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var blockedDelete: (id: String, users: [String])?

    private var editor: BindingsEditor { model.editor }

    var body: some View {
        @Bindable var model = model
        let document = editor.draft
        let ids = document.sortedActionIDs
        HStack(spacing: 0) {
            List(selection: $model.actionSelection) {
                ForEach(ids, id: \.self) { id in
                    let users = document.users(of: id).count
                    VStack(alignment: .leading, spacing: Space.xs / 2) {
                        Text(id).lineLimit(1)
                        Text("\(document.config.actions[id]!.displayName) · \(users == 0 ? "not used" : users == 1 ? "1 binding" : "\(users) bindings")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(id)
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { if let id = model.actionSelection { delete(id) } }
            .overlay {
                if ids.isEmpty {
                    ContentUnavailableView {
                        Label("No Actions", systemImage: "bolt")
                    } description: {
                        Text("Actions are what bindings do: open an app, run a command, send a shortcut.")
                    } actions: {
                        Button("New Action") { add() }
                    }
                }
            }
            .frame(width: Layout.listPaneWidth)
            Divider()
            if let id = model.actionSelection, let action = document.config.actions[id] {
                ActionForm(id: id, action: action)
                    .id(id)
            } else {
                ContentUnavailableView("No Selection", systemImage: "bolt",
                                       description: Text("Select an action to edit it."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Actions")
        .toolbar {
            ToolbarItemGroup {
                Button("New Action", systemImage: "plus") { add() }
                    .help("Add an action (⌘N)")
                Button("Delete Action", systemImage: "trash") { if let id = model.actionSelection { delete(id) } }
                    .help("Delete the selected action (⌫)")
                    .disabled(model.actionSelection == nil)
            }
        }
        .alert("Can't Delete “\(blockedDelete?.id ?? "")”",
               isPresented: Binding(get: { blockedDelete != nil }, set: { if !$0 { blockedDelete = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It's used by \(blockedDelete?.users.joined(separator: ", ") ?? ""). Change those bindings first.")
        }
    }

    private func add() {
        let id = editor.draft.freeActionID()
        editor.edit("New Action", undo: undo) { $0.setAction(id: id, .noop) }
        model.actionSelection = id
    }

    /// Deleting an action in use is blocked and lists its users (S-030).
    private func delete(_ id: String) {
        var users: [String] = []
        editor.edit("Delete Action", undo: undo) { document in
            do throws(ConfigDocument.EditError) { try document.removeAction(id) } catch {
                if case let .inUse(paths) = error { users = paths }
            }
        }
        if users.isEmpty { model.actionSelection = nil } else { blockedDelete = (id, users) }
    }
}

/// The form for one action: its id, its type, and that type's fields.
private struct ActionForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    let id: String
    let action: Config.Action
    @State private var newID = ""
    @State private var idProblem: String?

    var body: some View {
        Form {
            Section {
                TextField("ID", text: $newID)
                    .onSubmit(rename)
                    .textEntry("ID")
                if let idProblem {
                    Text(idProblem).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                Text("Bindings refer to the action by this id. Renaming it updates them.")
            }
            ActionFields(action: Binding(get: { action }, set: { update($0) }),
                         contexts: model.editor.draft.config.contexts)
        }
        .formStyle(.grouped)
        .onAppear { newID = id }
    }

    private func update(_ new: Config.Action) {
        guard new != action else { return }
        model.editor.edit("Change Action", undo: undo) { $0.setAction(id: id, new) }
    }

    private func rename() {
        let trimmed = newID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { idProblem = "Give the action an id."; return }
        var failed: ConfigDocument.EditError?
        model.editor.edit("Rename Action", undo: undo) { document in
            do throws(ConfigDocument.EditError) { try document.renameAction(id, to: trimmed) } catch { failed = error }
        }
        if case .idTaken = failed { idProblem = "Another action is already called “\(trimmed)”." } else {
            idProblem = nil
            model.actionSelection = trimmed
        }
    }
}

/// The fields for an action's type. Used again for each Context Aware
/// variant and its fallback, which can be any type except Context Aware.
struct ActionFields: View {
    @Binding var action: Config.Action
    let contexts: [Config.Context]
    var allowsContextAware = true

    var body: some View {
        Section {
            Picker("Type", selection: Binding(get: { action.type }, set: { action = .empty(of: $0) })) {
                ForEach(Config.Action.types(allowsContextAware: allowsContextAware), id: \.self) { type in
                    Text(Config.Action.empty(of: type).displayName).tag(type)
                }
            }
        }
        switch action {
        case let .application(bundleId, mode):
            Section {
                TextField("Bundle ID", text: text(bundleId) { .application(bundleId: $0, mode: mode) })
                    .textEntry("Bundle ID")
                Button("Choose App…") { chooseApp(mode: mode) }
                Picker("Mode", selection: Binding(get: { mode }, set: { action = .application(bundleId: bundleId, mode: $0) })) {
                    ForEach(Config.AppMode.menuOrder, id: \.self) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text(mode.explanation)
            }
        case let .open(target):
            Section {
                TextField("File, Folder or URL", text: text(target) { .open(target: $0) })
                    .textEntry("File, Folder or URL")
                Button("Choose…") { chooseFile() }
            } footer: {
                Text("A path starting with / or ~, or a URL such as https://example.com.")
            }
        case let .exec(command, cwd, env):
            Section {
                TextField("Command", text: Binding(
                    get: { command.joined(separator: "\n") },
                    set: { action = .exec(command: $0.split(separator: "\n").map(String.init), cwd: cwd, env: env) }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .textEntry("Command")
                TextField("Folder", text: Binding(
                    get: { cwd ?? "" },
                    set: { action = .exec(command: command, cwd: $0.isEmpty ? nil : $0, env: env) }),
                          prompt: Text("~"))
                    .textEntry("Folder")
            } footer: {
                Text("One argument per line, the program first. It runs with no shell, so nothing is expanded except a leading ~.")
            }
        case let .send(keys):
            Section {
                TextField("Keys", text: text(keys) { .send(keys: $0) }, prompt: Text("Cmd+F"))
                    .textEntry("Keys")
            } footer: {
                Text("One or more chords separated by spaces, such as Cmd+K S.")
            }
        case let .contextual(variants, fallback):
            ForEach(contexts, id: \.id) { context in
                Section("In \(context.id)") {
                    Toggle("Do Something in \(context.id)", isOn: Binding(
                        get: { variants[context.id] != nil },
                        set: { on in
                            var changed = variants
                            changed[context.id] = on ? .send(keys: "") : nil
                            action = .contextual(variants: changed, fallback: fallback)
                        }))
                }
                if let variant = variants[context.id] {
                    ActionFields(action: Binding(get: { variant }, set: { new in
                        var changed = variants
                        changed[context.id] = new
                        action = .contextual(variants: changed, fallback: fallback)
                    }), contexts: contexts, allowsContextAware: false)
                }
            }
            Section {
                Toggle("Otherwise, Do Something Else", isOn: Binding(
                    get: { fallback != nil },
                    set: { action = .contextual(variants: variants, fallback: $0 ? .send(keys: "") : nil) }))
            } footer: {
                Text(contexts.isEmpty ? "Add contexts on the Contexts page first."
                                      : "The first context, in Contexts order, that has the app in front wins.")
            }
            if let fallback {
                ActionFields(action: Binding(get: { fallback }, set: { action = .contextual(variants: variants, fallback: $0) }),
                             contexts: contexts, allowsContextAware: false)
            }
        case let .family(value):
            FamilyForm(action: $action, value: value.value)
        }
    }

    private func text(_ value: String, _ make: @escaping (String) -> Config.Action) -> Binding<String> {
        Binding(get: { value }, set: { action = make($0) })
    }

    /// An Open panel limited to apps (S-030).
    private func chooseApp(mode: Config.AppMode) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        action = .application(bundleId: id, mode: mode)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        let home = ActionPlanner.expandTilde("~", home: .homeDirectory)
        action = .open(target: path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path)
    }
}

extension Config.Action {
    /// The types for the Type picker, alphabetical by the name shown (S-046).
    static func types(allowsContextAware: Bool) -> [String] {
        let types = ["application", "open", "exec", "send"] + ActionRegistry.standard.kinds.map(\.type)
            + (allowsContextAware ? ["contextual"] : [])
        return types.sorted { empty(of: $0).displayName.localizedStandardCompare(empty(of: $1).displayName) == .orderedAscending }
    }

    /// A blank action of a type, for the type picker.
    static func empty(of type: String) -> Config.Action {
        switch type {
        case "application": .application(bundleId: "")
        case "open": .open(target: "")
        case "exec": .exec(command: [], cwd: nil, env: [:])
        case "send": .send(keys: "")
        case "contextual": .contextual(variants: [:], fallback: nil)
        default:
            ActionRegistry.standard.family(for: type).map { .family(AnyActionValue($0.blank(type))) } ?? .noop
        }
    }
}

extension Config.AppMode {
    /// The Mode picker's order, as the modes are named in the glossary.
    static let menuOrder: [Config.AppMode] = [.focus, .start, .focusOrStart]

    /// The footer under the Mode picker.
    var explanation: String {
        switch self {
        case .focusOrStart: "Brings the app forward, starting it first if it isn't running."
        case .focus: "Brings the app forward if it's running. Otherwise nothing happens and the Guide says so."
        case .start: "Starts a new copy of the app, even if one is already running."
        }
    }
}
