import SwiftUI
import UnnamedManagerKit

/// What the Help page lists (S-052), worked out from the config so the
/// self-test can check it and it never drifts from your bindings.
struct HelpContent: Equatable {
    struct Row: Equatable, Identifiable {
        var key: String
        var title: String
        var isMenu: Bool
        var path: KeySequence
        var id: String { path.description }
    }

    struct Group: Equatable, Identifiable {
        var title: String
        var rows: [Row]
        var id: String { title }
    }

    /// One built-in action (S-081): what it does and the name a binding uses.
    struct BuiltIn: Equatable, Identifiable {
        var title: String
        var name: String
        /// Your config has an action with this name, which runs instead.
        var isOverridden: Bool
        var id: String { name }
    }

    struct BuiltInGroup: Equatable, Identifiable {
        var title: String
        var rows: [BuiltIn]
        var id: String { title }
    }

    /// Every leader and direct binding, grouped as Home groups them, in file order.
    var groups: [Group]
    /// Every built-in action, kind by kind, with a row for numbered targets.
    var builtIns: [BuiltInGroup]
    var cancelKey: String
    /// nil when Back is turned off.
    var backKey: String?
    /// True when Back in a leader's menu opens Home (S-050).
    var hasHome: Bool

    /// The Held Menus section, to scroll to (S-094).
    static let heldMenusID = "Held Menus"
    static let readme = URL(string: "https://github.com/juyanith/unnamed-manager-mac#readme")!
    static let issues = URL(string: "https://github.com/juyanith/unnamed-manager-mac/issues")!

    init(config: LoadedConfig?) {
        let leaders = config?.leaders ?? []
        let home = Home(leaders: leaders, current: leaders.first?.path.leader.modifiers ?? [])
        groups = home.groups.map { group in
            Group(title: group.title, rows: group.entries.map {
                Row(key: $0.path.leader.key.name, title: $0.title, isMenu: $0.isMenu, path: $0.path)
            })
        }
        cancelKey = GuideContent.footerLabel(config?.cancelKey ?? .escape)
        backKey = config.map { $0.backKey.map(GuideContent.footerLabel) } ?? GuideContent.footerLabel(.backspace)
        hasHome = leaders.count > 1
        let defined = Set(config?.config.actions.keys.map { $0 } ?? [])
        builtIns = BuiltInAction.groups.map { group in
            var rows = group.entries.map {
                BuiltIn(title: $0.action.builtInValueName ?? group.name, name: $0.name, isOverridden: defined.contains($0.name))
            }
            // Focus Window and Swap Window take any number, which the list can't hold.
            if let first = group.entries.first?.name, first.hasPrefix("window-focus-") || first.hasPrefix("window-swap-") {
                let prefix = first.hasPrefix("window-focus-") ? "window-focus-" : "window-swap-"
                rows.append(BuiltIn(title: "Window 1, 2, 3…", name: "\(prefix)1, \(prefix)2, …", isOverridden: false))
            }
            return BuiltInGroup(title: group.name, rows: rows)
        }
    }

    var isEmpty: Bool { groups.isEmpty }
}

/// The Help window (S-052): your leaders and direct
/// bindings, the keys that work in every sequence, the words, and links.
struct HelpPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    private var editor: BindingsEditor { model.editor }

    /// The draft, so the page matches the Bindings tab, even mid-edit.
    private var content: HelpContent {
        let draft = editor.draft
        if draft.config.entries.isEmpty { return HelpContent(config: nil) }
        return HelpContent(config: (try? draft.validate().get()) ?? model.store.loaded)
    }

    var body: some View {
        let content = content
        ScrollViewReader { scroller in
        Form {
            if content.isEmpty {
                ContentUnavailableView {
                    Label("No Bindings", systemImage: "keyboard")
                } description: {
                    Text("Add a leader such as Hyper+Space with keys under it, or a direct binding such as Hyper+T. Your keys are listed here.")
                } actions: {
                    Button("New Binding") {
                        model.showSettings(.bindings)
                        editor.addBinding(undo: undo)
                    }
                }
            } else {
                yourKeys(content)
            }
            inASequence(content)
            heldMenus
            builtIns(content)
            words
            more
        }
        .formStyle(.grouped)
        .readableWidth(Layout.helpMaxWidth)
        .onChange(of: model.revealBuiltIn, initial: true) { _, kind in
            guard let kind else { return }
            Task {
                try? await Task.sleep(for: Motion.layoutSettle)
                scroller.scrollTo(kind, anchor: .top)
                model.revealBuiltIn = nil
            }
        }
        }
    }

    @ViewBuilder
    private func yourKeys(_ content: HelpContent) -> some View {
        ForEach(content.groups) { group in
            Section {
                ForEach(group.rows) { row in
                    Button { show(row.path) } label: { rowLabel(row) }
                        .buttonStyle(.plain)
                        .help("Show \(row.title) on Settings' Bindings tab")
                }
            } header: {
                Text(group.id == content.groups.first?.id ? "Your Keys: \(group.title)" : group.title)
            } footer: {
                if group.id == content.groups.last?.id {
                    Text("Press a leader to start a sequence, or a direct binding to run its action at once. Click one to see it on Settings' Bindings tab.")
                }
            }
        }
    }

    private func rowLabel(_ row: HelpContent.Row) -> some View {
        HStack(spacing: Space.sm) {
            Keycap(label: row.key)
            Text(row.title)
            Spacer()
            Text(row.isMenu ? "Leader" : "Direct binding")
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.forward")
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.key), \(row.title), \(row.isMenu ? "leader" : "direct binding")")
        .accessibilityAddTraits(.isButton)
    }

    private func inASequence(_ content: HelpContent) -> some View {
        Section {
            keyRow(content.cancelKey, "Cancel", "Ends the sequence without running anything.")
            if let back = content.backKey {
                keyRow(back, "Back", content.hasHome
                       ? "Goes up one menu. In a leader's menu, it opens Home, which lists every leader and direct binding."
                       : "Goes up one menu. In a leader's menu, it ends the sequence.")
            }
            described(Text("Guide"), "Pause during a sequence and the Guide shows where you are and which keys come next.")
        } header: {
            Text("In a Sequence")
        } footer: {
            Text("Change the Cancel and Back keys and when the Guide appears in Settings › General (⌘,).")
        }
    }

    /// Held menus (S-094): how a leader with Hold to Choose works.
    private var heldMenus: some View {
        Section {
            described(Text("Hold"), "Keep the leader's modifiers down. The Guide shows the menu with its first item highlighted.")
            described(Text("Repeat key"), "Press the key that opened the menu again to move the highlight, as Tab does in ⌘Tab. Down and Up move it too.")
            described(Text("Shift"), "Hold Shift with the repeat key to move the highlight back.")
            described(Text("Let go"), "Let go of a modifier to choose the highlighted item. Press an item's key to highlight it at once.")
            described(Text("Cancel"), "The first row. Let go on it, or press \(GuideContent.footerLabel(model.store.loaded?.cancelKey ?? .escape)), to choose nothing.")
        } header: {
            Text("Held Menus")
        } footer: {
            Text("Turn on Hold to Choose for a leader on Settings' Bindings tab. A menu whose Contents is Recent Windows lists the windows you used last.")
        }
        .id(HelpContent.heldMenusID)
    }

    /// Built-in actions (S-081): a row for a kind with one, and a list to open for a kind with several.
    private func builtIns(_ content: HelpContent) -> some View {
        Section {
            ForEach(content.builtIns) { group in
                if group.rows.count == 1 {
                    builtInRow(group.rows[0])
                } else {
                    DisclosureGroup(isExpanded: Binding(
                        get: { model.openBuiltIns.contains(group.title) },
                        set: { if $0 { model.openBuiltIns.insert(group.title) } else { model.openBuiltIns.remove(group.title) } })) {
                        ForEach(group.rows) { builtInRow($0) }
                    } label: {
                        LabeledContent(group.title, value: "\(group.rows.count) actions")
                    }
                    .id(group.title)
                }
            }
        } header: {
            Text("Built-In Actions")
        } footer: {
            Text("A binding can use these with nothing to set up: choose one from its Built In menu, or write its name as the binding's action in the config file. An action of your own with the same name overrides it.")
        }
    }

    private func builtInRow(_ row: HelpContent.BuiltIn) -> some View {
        LabeledContent {
            Text(row.name)
                .font(.body.monospaced())
                .textSelection(.enabled)
        } label: {
            Text(row.title)
            if row.isOverridden { Text("Overridden by your action") }
        }
    }

    private func keyRow(_ key: String, _ title: String, _ text: String) -> some View {
        described(HStack(spacing: Space.sm) {
            Keycap(label: key)
            Text(title)
        }, text)
    }

    /// A title with a line or two under it in secondary text.
    private func described(_ title: some View, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            title
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var words: some View {
        Section("Words") {
            word("Leader", "A chord such as Hyper+Space that starts a sequence and opens its menu.")
            word("Menu", "A group of keys inside a sequence. It opens more choices and runs nothing itself.")
            word("Binding", "A key that runs an action, such as E for Editor.")
            word("Direct binding", "A chord such as Hyper+T that runs its action at once, with no sequence.")
            word("Action", "What a binding does: use an app, open a file or URL, run a command, or send a shortcut.")
        }
    }

    private func word(_ term: String, _ meaning: String) -> some View {
        described(Text(term), meaning)
    }

    private var more: some View {
        Section {
            Button("Open Config File") { model.store.openFile() }
            Link("Read the Documentation on GitHub", destination: HelpContent.readme)
            Link("Report a Problem", destination: HelpContent.issues)
        } header: {
            Text("More")
        } footer: {
            Text(AppVersion.line)
        }
    }

    private func show(_ path: KeySequence) {
        editor.selection = path
        model.showSettings(.bindings)
    }
}
