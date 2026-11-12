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

    /// Every leader and direct binding, grouped as Home groups them, in file order.
    var groups: [Group]
    var cancelKey: String
    /// nil when Back is turned off.
    var backKey: String?
    /// True when Back in a leader's menu opens Home (S-050).
    var hasHome: Bool

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
    }

    var isEmpty: Bool { groups.isEmpty }
}

/// The Help page of the Bindings window (S-052): your leaders and direct
/// bindings, the keys that work in every sequence, the words, and links.
struct HelpPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    /// The form's side margins, which keep its rows readable in a wide window.
    @State private var sideMargin = Space.margin

    private var editor: BindingsEditor { model.editor }

    /// The draft, so the page matches the Bindings page, even mid-edit.
    private var content: HelpContent {
        let draft = editor.draft
        if draft.config.entries.isEmpty { return HelpContent(config: nil) }
        return HelpContent(config: (try? draft.validate().get()) ?? model.store.loaded)
    }

    var body: some View {
        let content = content
        Form {
            if content.isEmpty {
                ContentUnavailableView {
                    Label("No Bindings", systemImage: "keyboard")
                } description: {
                    Text("Add a leader such as Hyper+Space with keys under it, or a direct binding such as Hyper+T. Your keys are listed here.")
                } actions: {
                    Button("New Binding") {
                        model.sidebar = .bindings
                        editor.addBinding(undo: undo)
                    }
                }
            } else {
                yourKeys(content)
            }
            inASequence(content)
            words
            more
        }
        .formStyle(.grouped)
        // Centered by margins, not a narrower frame, so the scroll view and
        // its background still fill the page.
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            sideMargin = max(Space.margin, ((width - Layout.helpMaxWidth) / 2).rounded())
        }
        .navigationTitle("Help")
    }

    @ViewBuilder
    private func yourKeys(_ content: HelpContent) -> some View {
        ForEach(content.groups) { group in
            Section {
                ForEach(group.rows) { row in
                    Button { show(row.path) } label: { rowLabel(row) }
                        .buttonStyle(.plain)
                        .help("Show \(row.title) on the Bindings page")
                }
            } header: {
                Text(group.id == content.groups.first?.id ? "Your Keys: \(group.title)" : group.title)
            } footer: {
                if group.id == content.groups.last?.id {
                    Text("Press a leader to start a sequence, or a direct binding to run its action at once. Click one to see it on the Bindings page.")
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
            Text("Change the Cancel and Back keys and when the Guide appears in Settings (⌘,).")
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
        model.sidebar = .bindings
    }
}
