import ServiceManagement
import SwiftUI
import UnnamedManagerKit

/// The General and Windows tabs of Settings: a grouped Form each, 520 pt
/// wide. General has Guide, Keys, Feedback and Startup; Windows has
/// Windows, Focus and Swap, and Apps (S-032, S-036, S-082, S-084, S-085).
/// Changes are written to the config file at once, like every other edit.
struct SettingsForm: View {
    let tab: SettingsTab
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    private var editor: BindingsEditor { model.editor }
    private var runtime: Config.Runtime { editor.draft.config.runtime }
    private var ui: Config.UI { editor.draft.config.ui }

    var body: some View {
        Form {
            switch tab {
            case .windows:
                Section {
                    LabeledContent("Gap Between Windows") {
                        PointsField(value: windowDistance(\.gap, "Change Gap"), range: 0...64, step: 2,
                                    accessibilityLabel: "Gap between windows, points")
                    }
                    Picker("Maximum Columns", selection: windowLimit(\.maxColumns, "Change Maximum Columns")) {
                        ForEach(Array(Config.Windows.limitRange), id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Maximum Rows", selection: windowLimit(\.maxRows, "Change Maximum Rows")) {
                        ForEach(Array(Config.Windows.limitRange), id: \.self) { Text("\($0)").tag($0) }
                    }
                } header: {
                    Text("Windows")
                } footer: {
                    Text("Place Window, Fill and Arrange Windows leave the gap between a window and the screen's edges, and between windows side by side. 0 puts them edge to edge. The maximums limit the grid Arrange Windows picks when its action leaves Groups on Automatic.")
                }

                Section {
                    LabeledContent("Smallest Visible Part") {
                        PointsField(value: windowDistance(\.minVisible, "Change Smallest Visible Part"), range: 0...200, step: 5,
                                    accessibilityLabel: "Smallest visible part, points")
                    }
                    LabeledContent("Same Row Within") {
                        PointsField(value: windowDistance(\.rowTolerance, "Change Same Row Within"), range: 0...200, step: 5,
                                    accessibilityLabel: "Same row within, points")
                    }
                    LabeledContent("Equally Near Within") {
                        PointsField(value: windowDistance(\.tieTolerance, "Change Equally Near Within"), range: 0...20, step: 1,
                                    accessibilityLabel: "Equally near within, points")
                    }
                } header: {
                    Text("Focus and Swap")
                } footer: {
                    Text("Focus Window and Swap Window only pick windows you can see. A window counts when a square this size shows, and for Left, Right, Up and Down, it must line up with yours by as much. Windows whose tops are this close share a row in the order. Windows this close to equally near count as tied, and the one lined up more wins.")
                }

                Section {
                    let apps = editor.draft.config.windows.apps
                    if !apps.isEmpty {
                        HStack(spacing: Space.sm) {
                            Text("App")
                            Spacer()
                            ForEach(Self.rules, id: \.name) { Text($0.name).frame(width: Layout.ruleColumnWidth) }
                            // Room for the Remove button.
                            Image(systemName: "minus.circle").hidden()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                    ForEach(apps.keys.sorted { AppIcon.name($0).localizedStandardCompare(AppIcon.name($1)) == .orderedAscending }, id: \.self) { bundleId in
                        HStack(spacing: Space.sm) {
                            AppIcon(bundleId: bundleId)
                            VStack(alignment: .leading) {
                                Text(AppIcon.name(bundleId))
                                Text(bundleId).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ForEach(Self.rules, id: \.name) { rule in
                                Toggle(rule.name, isOn: takesPart(bundleId, in: rule.path))
                                    .labelsHidden()
                                    .frame(width: Layout.ruleColumnWidth)
                                    .help("\(rule.help) \(AppIcon.name(bundleId))'s windows")
                                    .accessibilityLabel("\(rule.name) for \(AppIcon.name(bundleId))")
                            }
                            Button("Remove", systemImage: "minus.circle") {
                                editApps { $0[bundleId] = nil }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Let every window action pick \(AppIcon.name(bundleId)) again")
                        }
                        .toggleStyle(.checkbox)
                    }
                    Button("Add App…") { addApps() }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Uncheck what an app's windows stay out of. Focus: Focus Window never picks them, Window Used Before too. Swap: Swap Window never moves them. Arrange: Arrange Windows never counts or moves them. Their windows still hide the ones behind them.")
                }
            default:
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
                    Text("What happens when you press a key the current menu doesn't have. The alert sound also plays when Focus Window or Swap Window finds no window there.")
                }

                Section {
                    Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                } header: {
                    Text("Startup")
                } footer: {
                    Text("You can also change this in System Settings › General › Login Items.")
                }
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

    /// The gap (S-071) or one of Focus Window's distances (S-082), in points.
    private func windowDistance(_ key: WritableKeyPath<Config.Windows, Double>, _ name: String) -> Binding<Double> {
        Binding(get: { editor.draft.config.windows[keyPath: key] }, set: { value in
            guard editor.draft.config.windows[keyPath: key] != value else { return }
            editor.edit(name, undo: undo) { $0.config.windows[keyPath: key] = value }
        })
    }

    /// The columns of the Apps table: each rule in `windows.apps` (S-084, spec v15).
    static let rules: [(name: String, path: WritableKeyPath<Config.Windows.AppRules, Bool>, help: String)] = [
        ("Focus", \.focus, "Focus Window picks"),
        ("Swap", \.swap, "Swap Window moves"),
        ("Arrange", \.arrange, "Arrange Windows moves"),
    ]

    private func editApps(_ change: (inout [String: Config.Windows.AppRules]) -> Void) {
        editor.edit("Change App Rules", undo: undo) { change(&$0.config.windows.apps) }
    }

    /// Whether a window action takes part with an app's windows.
    private func takesPart(_ app: String, in rule: WritableKeyPath<Config.Windows.AppRules, Bool>) -> Binding<Bool> {
        Binding(get: { editor.draft.config.windows.apps[app]?[keyPath: rule] ?? true }, set: { isOn in
            editApps { $0[app, default: Config.Windows.AppRules()][keyPath: rule] = isOn }
        })
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .filter { editor.draft.config.windows.apps[$0] == nil }
        // A new app starts left out of everything, since that's why it's added.
        editApps { apps in
            for app in added { apps[app] = .leftOutOfAll }
        }
    }

    /// One of Arrange Windows' limits (S-076).
    private func windowLimit(_ key: WritableKeyPath<Config.Windows, Int>, _ name: String) -> Binding<Int> {
        Binding(get: { editor.draft.config.windows[keyPath: key] }, set: { value in
            guard editor.draft.config.windows[keyPath: key] != value else { return }
            editor.edit(name, undo: undo) { $0.config.windows[keyPath: key] = value }
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

/// A distance in whole points within a range: the gap around placed
/// windows (S-071) and Focus Window's distances (S-082).
struct PointsField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityLabel: String

    private func clamped(_ new: Double) -> Double { min(max(new.rounded(), range.lowerBound), range.upperBound) }

    var body: some View {
        HStack(spacing: Space.sm) {
            TextField("Points", value: Binding(get: { value }, set: { value = clamped($0) }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.keyColumnWidth / 2)
                .accessibilityLabel(accessibilityLabel)
            Stepper("Points", value: Binding(get: { value }, set: { value = clamped($0) }), in: range, step: step)
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
