import AppKit
import SwiftUI
import UnnamedManagerKit

/// A count of steps, from 1 to 96 (spec v24), laid out as PointsField.
struct StepsField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        let range = WindowSteps.range
        let clamped = Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
        LabeledContent(title) {
            HStack(spacing: Space.sm) {
                TextField("Steps", value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Layout.keyColumnWidth / 2)
                    .accessibilityLabel("\(title), steps")
                Stepper("Steps", value: clamped, in: range)
                    .labelsHidden()
                Text("steps").foregroundStyle(.secondary)
            }
        }
    }
}

/// The Displays section of the Windows tab (S-101): one display's steps
/// and smallest cell, picked from the connected displays and the ones the
/// file already has settings for.
struct DisplaysSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var picked: String?

    /// A display to pick, by its key in `windows.displays`.
    struct Choice: Identifiable {
        let id: String
        let name: String
        let size: CGSize
    }

    private var windows: Config.Windows { model.editor.draft.config.windows }

    /// Connected displays first, as macOS orders them; two of the same size
    /// share one choice, since they share their settings. Then the displays
    /// the file has settings for that aren't connected.
    static func choices(screens: [NSScreen], saved: some Collection<String>) -> [Choice] {
        var choices: [Choice] = []
        for screen in screens {
            let key = Config.Windows.displayKey(for: screen.frame.size)
            if let at = choices.firstIndex(where: { $0.id == key }) {
                choices[at] = Choice(id: key, name: choices[at].name + ", " + screen.localizedName, size: choices[at].size)
            } else {
                choices.append(Choice(id: key, name: screen.localizedName, size: screen.frame.size))
            }
        }
        for key in saved.sorted() where !choices.contains(where: { $0.id == key }) {
            if let size = Config.Windows.size(ofDisplayKey: key) {
                choices.append(Choice(id: key, name: "Not Connected", size: size))
            }
        }
        return choices
    }

    var body: some View {
        let choices = Self.choices(screens: NSScreen.screens, saved: windows.displays.keys)
        let choice = choices.first { $0.id == picked } ?? choices.first
        Section {
            if let choice {
                Picker("Display", selection: Binding(get: { choice.id }, set: { picked = $0 })) {
                    ForEach(choices) { choice in
                        Text(verbatim: "\(choice.name) (\(Int(choice.size.width)) × \(Int(choice.size.height)))").tag(choice.id)
                    }
                }
                StepsField(title: "Steps Across", value: steps(\.across, of: choice))
                StepsField(title: "Steps Down", value: steps(\.down, of: choice))
                StepsField(title: "Smallest Cell Across", value: cell(\.across, of: choice))
                StepsField(title: "Smallest Cell Down", value: cell(\.down, of: choice))
                Button("Use Defaults") {
                    model.editor.edit("Use Display Defaults", undo: undo) { $0.config.windows.displays[choice.id] = nil }
                }
                .disabled(windows.displays[choice.id] == nil)
            }
        } header: {
            Text("Displays")
        } footer: {
            Text("A display's steps start from its shape, and its smallest cell from the one above. Change them for the display picked: more steps across on a wide display gives Arrange Windows and Tidy Windows finer columns. Displays of the same size share these settings.")
        }
    }

    /// One count of a display's steps, which start as the guess.
    private func steps(_ count: WritableKeyPath<WindowSteps, Int>, of choice: Choice) -> Binding<Int> {
        Binding(get: { windows.steps(for: choice.size)[keyPath: count] }, set: { value in
            var steps = windows.steps(for: choice.size)
            guard steps[keyPath: count] != value else { return }
            steps[keyPath: count] = value
            model.editor.edit("Change Display Steps", undo: undo) { $0.config.windows.setSteps(steps, for: choice.size) }
        })
    }

    /// One count of a display's smallest cell, which starts as `minCell`.
    private func cell(_ count: WritableKeyPath<WindowSteps, Int>, of choice: Choice) -> Binding<Int> {
        let current = { windows.displays[choice.id]?.minCell ?? windows.minCell }
        return Binding(get: { current()[keyPath: count] }, set: { value in
            var cell = current()
            guard cell[keyPath: count] != value else { return }
            cell[keyPath: count] = value
            model.editor.edit("Change Display Smallest Cell", undo: undo) { $0.config.windows.setMinCell(cell, for: choice.size) }
        })
    }
}

/// An app's smallest window size in the Apps table (spec v24): the size,
/// or Any, opening a popover with its width and height.
struct AppSizeButton: View {
    let bundleId: String
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo

    private var rules: Config.Windows.AppRules { model.editor.draft.config.windows.apps[bundleId] ?? .init() }

    static func label(width: Double, height: Double) -> String {
        guard width > 0 || height > 0 else { return "Any" }
        let side = { (value: Double) in value > 0 ? Int(value).formatted() : "Any" }
        return "\(side(width)) × \(side(height))"
    }

    var body: some View {
        @Bindable var model = model
        Button(Self.label(width: rules.minWidth, height: rules.minHeight)) { model.appSizeShown = bundleId }
            .buttonStyle(.borderless)
            .monospacedDigit()
            .help("The smallest size Arrange Windows and Tidy Windows give \(AppIcon.name(bundleId))'s windows")
            .accessibilityLabel("Smallest size for \(AppIcon.name(bundleId))")
            .popover(isPresented: Binding(get: { model.appSizeShown == bundleId },
                                          set: { if !$0, model.appSizeShown == bundleId { model.appSizeShown = nil } }),
                     arrowEdge: .bottom) {
                Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
                    GridRow {
                        Text("Smallest Width")
                        PointsField(value: size(\.minWidth, "Change Smallest Width"), range: 0...10_000, step: 10,
                                    accessibilityLabel: "Smallest width, points")
                    }
                    GridRow {
                        Text("Smallest Height")
                        PointsField(value: size(\.minHeight, "Change Smallest Height"), range: 0...10_000, step: 10,
                                    accessibilityLabel: "Smallest height, points")
                    }
                    Text("Arrange Windows and Tidy Windows give \(AppIcon.name(bundleId))'s windows at least this much room. 0 is any size.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Layout.sizePopoverTextWidth, alignment: .leading)
                        .gridCellColumns(2)
                }
                .padding(Space.lg)
                .noInitialFocus()
            }
    }

    private func size(_ side: WritableKeyPath<Config.Windows.AppRules, Double>, _ name: String) -> Binding<Double> {
        Binding(get: { rules[keyPath: side] }, set: { value in
            guard rules[keyPath: side] != value else { return }
            model.editor.edit(name, undo: undo) { $0.config.windows.apps[bundleId, default: .init()][keyPath: side] = value }
        })
    }
}
