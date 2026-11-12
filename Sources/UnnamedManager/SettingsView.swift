import ServiceManagement
import SwiftUI
import UnnamedManagerKit

/// The Settings window (Settings…, ⌘,): one grouped Form, 520 pt wide,
/// with Guide, Keys, Feedback and Startup (S-032, S-036). Changes are
/// written to the config file at once, like every other edit.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    private var editor: BindingsEditor { model.editor }
    private var runtime: Config.Runtime { editor.draft.config.runtime }
    private var ui: Config.UI { editor.draft.config.ui }

    var body: some View {
        Form {
            Section {
                Toggle("Show Guide", isOn: runtimeBinding(\.showHud, "Show Guide"))
                LabeledContent("Delay Before Showing") {
                    MillisecondsField(value: runtimeBinding(\.hudDelayMs, "Change Delay"))
                }
                .disabled(!runtime.showHud)
                LabeledContent("Close After") {
                    MillisecondsField(value: runtimeBinding(\.timeoutMs, "Change Timeout"), zeroLabel: "Never")
                }
                .disabled(!runtime.showHud)
                Picker("Position", selection: uiBinding(\.position, "Change Position")) {
                    Text("Center").tag("center")
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                Picker("Appearance", selection: uiBinding(\.theme, "Change Appearance")) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } header: {
                Text("Guide")
            } footer: {
                Text("With a delay, a sequence you know runs with nothing on screen. The Guide appears when you pause.")
            }

            Section {
                Picker("Cancel", selection: runtimeBinding(\.cancelKey, "Change Cancel Key")) {
                    ForEach(Self.controlKeys, id: \.self) { Text($0).tag($0) }
                }
                Picker("Back", selection: runtimeBinding(\.backKey, "Change Back Key")) {
                    Text("None").tag("")
                    ForEach(Self.controlKeys, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("Cancel ends a sequence without running anything. Back goes up one menu. Neither can be used as a key inside a menu.")
            }

            Section {
                Toggle("Flash on a Key That Isn't Bound", isOn: uiBinding(\.errorFlash, "Change Flash"))
                Toggle("Play Alert Sound", isOn: uiBinding(\.errorBell, "Change Alert Sound"))
            } header: {
                Text("Feedback")
            } footer: {
                Text("What happens when you press a key the current menu doesn't have.")
            }

            Section {
                LabeledContent("Gap Between Windows") {
                    GapField(value: Binding(get: { editor.draft.config.windows.gap }, set: { value in
                        guard editor.draft.config.windows.gap != value else { return }
                        editor.edit("Change Gap", undo: undo) { $0.config.windows.gap = value }
                    }))
                }
            } header: {
                Text("Windows")
            } footer: {
                Text("Place Window leaves this space between a window and the screen's edges, and between windows side by side. 0 puts them edge to edge.")
            }

            Section {
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
            } header: {
                Text("Startup")
            } footer: {
                Text("You can also change this in System Settings › General › Login Items.")
            }

            if !editor.draftErrors.isEmpty {
                Section {
                    ForEach(Array(editor.draftErrors.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Surfaces.warning)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent(max: Layout.settingsMaxHeight)
        .frame(width: Layout.settingsWidth)
        .noInitialFocus()
        .onAppear { opensAtLogin = SMAppService.mainApp.status == .enabled }
    }

    /// Keys that make sense for Cancel and Back.
    static let controlKeys = ["Escape", "Backspace", "Delete", "Tab", "Grave", "Q"]

    private func runtimeBinding<T: Equatable>(_ key: WritableKeyPath<Config.Runtime, T>, _ name: String) -> Binding<T> {
        Binding(get: { runtime[keyPath: key] }, set: { value in
            guard runtime[keyPath: key] != value else { return }
            editor.edit(name, undo: undo) { $0.config.runtime[keyPath: key] = value }
        })
    }

    private func uiBinding<T: Equatable>(_ key: WritableKeyPath<Config.UI, T>, _ name: String) -> Binding<T> {
        Binding(get: { ui[keyPath: key] }, set: { value in
            guard ui[keyPath: key] != value else { return }
            editor.edit(name, undo: undo) { $0.config.ui[keyPath: key] = value }
        })
    }

    /// Registers or unregisters the login item, then shows what macOS says (S-036).
    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("Open at Login: \(error.localizedDescription, privacy: .public)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// The gap around placed windows, in whole points from 0 to 64 (S-071).
struct GapField: View {
    @Binding var value: Double

    private func clamped(_ new: Double) -> Double { min(max(new.rounded(), 0), 64) }

    var body: some View {
        HStack(spacing: Space.sm) {
            TextField("Points", value: Binding(get: { value }, set: { value = clamped($0) }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.keyColumnWidth / 2)
                .accessibilityLabel("Gap between windows, points")
            Stepper("Points", value: Binding(get: { value }, set: { value = clamped($0) }), in: 0...64, step: 2)
                .labelsHidden()
            Text("pt").foregroundStyle(.secondary)
        }
    }
}

/// A number of milliseconds that can't go below zero (S-032).
struct MillisecondsField: View {
    @Binding var value: Int
    var zeroLabel = "No Delay"

    var body: some View {
        HStack(spacing: Space.sm) {
            TextField("Milliseconds", value: Binding(get: { value }, set: { value = SettingsValues.milliseconds($0) }),
                      format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.keyColumnWidth / 2)
            Stepper("Milliseconds", value: Binding(get: { value }, set: { value = SettingsValues.milliseconds($0) }),
                    in: 0...60_000, step: 100)
                .labelsHidden()
            Text(value == 0 ? zeroLabel : "ms").foregroundStyle(.secondary)
        }
    }
}
