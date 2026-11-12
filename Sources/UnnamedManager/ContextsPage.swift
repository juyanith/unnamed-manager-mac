import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UnnamedManagerKit

/// The Contexts page (S-031): contexts in order, each with its apps.
/// Order matters, because the first context with the app in front wins.
struct ContextsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    private var editor: BindingsEditor { model.editor }

    var body: some View {
        @Bindable var model = model
        let contexts = editor.draft.config.contexts
        HStack(spacing: 0) {
            List(selection: $model.contextSelection) {
                ForEach(contexts, id: \.id) { context in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(context.id)
                        HStack(spacing: Space.xs) {
                            ForEach(context.apps.prefix(8), id: \.self) { AppIcon(bundleId: $0) }
                        }
                    }
                    .tag(context.id)
                }
                .onMove { source, destination in
                    editor.edit("Move Context", undo: undo) { $0.moveContexts(from: source, to: destination) }
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { if let id = model.contextSelection { delete(id) } }
            .overlay {
                if contexts.isEmpty {
                    ContentUnavailableView {
                        Label("No Contexts", systemImage: "macwindow.on.rectangle")
                    } description: {
                        Text("A context is a set of apps, such as your browsers, that Context Aware actions check.")
                    } actions: {
                        Button("New Context") { add() }
                    }
                }
            }
            .frame(width: Layout.listPaneWidth)
            Divider()
            if let id = model.contextSelection, let context = contexts.first(where: { $0.id == id }) {
                ContextForm(context: context).id(id)
            } else {
                ContentUnavailableView("No Selection", systemImage: "macwindow.on.rectangle",
                                       description: Text("Select a context to edit its apps."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Contexts")
        .toolbar {
            ToolbarItemGroup {
                Button("New Context", systemImage: "plus") { add() }
                    .help("Add a context (⌘N)")
                Button("Delete Context", systemImage: "trash") { if let id = model.contextSelection { delete(id) } }
                    .help("Delete the selected context (⌫)")
                    .disabled(model.contextSelection == nil)
            }
        }
    }

    private func add() {
        var id = "new-context"
        var n = 2
        while editor.draft.config.contexts.contains(where: { $0.id == id }) { id = "new-context-\(n)"; n += 1 }
        editor.edit("New Context", undo: undo) { $0.config.contexts.append(Config.Context(id: id, apps: [])) }
        model.contextSelection = id
    }

    private func delete(_ id: String) {
        editor.edit("Delete Context", undo: undo) { $0.config.contexts.removeAll { $0.id == id } }
        model.contextSelection = nil
    }
}

private struct ContextForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    let context: Config.Context
    @State private var newID = ""
    @State private var idProblem: String?

    var body: some View {
        Form {
            Section {
                TextField("ID", text: $newID).onSubmit(rename).textEntry("ID")
                if let idProblem { Text(idProblem).font(.callout).foregroundStyle(.red) }
            } footer: {
                Text("Context Aware variants refer to the context by this id.")
            }
            Section {
                ForEach(context.apps, id: \.self) { bundleId in
                    HStack(spacing: Space.sm) {
                        AppIcon(bundleId: bundleId)
                        VStack(alignment: .leading) {
                            Text(AppIcon.name(bundleId))
                            Text(bundleId).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { setApps(context.apps.filter { $0 != bundleId }) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remove \(AppIcon.name(bundleId)) from \(context.id)")
                    }
                }
                Button("Add App…") { addApp() }
            } header: {
                Text("Apps")
            } footer: {
                Text("When an app is in more than one context, Context Aware uses the first one in the list. Drag contexts to change the order.")
            }
        }
        .formStyle(.grouped)
        .onAppear { newID = context.id }
    }

    private func setApps(_ apps: [String]) {
        model.editor.edit("Change Apps", undo: undo) { document in
            if let i = document.config.contexts.firstIndex(where: { $0.id == context.id }) {
                document.config.contexts[i].apps = apps
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !context.apps.contains($0) }
        setApps(context.apps + ids)
    }

    private func rename() {
        let trimmed = newID.trimmingCharacters(in: .whitespaces)
        var failed = false
        model.editor.edit("Rename Context", undo: undo) { document in
            do throws(ConfigDocument.EditError) { try document.renameContext(context.id, to: trimmed) } catch { failed = true }
        }
        if failed { idProblem = "Another context is already called “\(trimmed)”." } else {
            idProblem = nil
            model.contextSelection = trimmed
        }
    }
}

/// An app's icon from its bundle id, or a placeholder when it isn't installed.
struct AppIcon: View {
    let bundleId: String

    var body: some View {
        Image(nsImage: Self.icon(bundleId))
            .resizable()
            .frame(width: Space.lg + Space.xs, height: Space.lg + Space.xs)
            .help(Self.name(bundleId))
            .accessibilityLabel(Self.name(bundleId))
    }

    static func icon(_ bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    static func name(_ bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "")
    }
}
