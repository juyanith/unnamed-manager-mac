import SwiftUI
import UnnamedManagerKit

// The names and number fields the window action forms share (S-070).

// MARK: - Names

extension FocusDirection {
    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .up: "Up"
        case .down: "Down"
        case .next: "Next Window"
        case .previous: "Previous Window"
        case .first: "First Window"
        case .last: "Last Window"
        case .recent: "Window Used Before"
        }
    }
}

extension WindowTarget {
    var displayName: String {
        switch self {
        case let .window(direction): direction.displayName
        case let .number(number): "Window \(number)"
        }
    }
}

extension ArrangeCount {
    var displayName: String {
        switch self {
        case let .windows(number): "Last \(number)"
        case .all: "All on the Display"
        }
    }
}

extension ResizeStep {
    var displayName: String {
        switch self {
        case .grow: "Grow Through Widths"
        case .shrink: "Shrink Through Widths"
        }
    }
}

extension Config.Action {
    /// The value a built-in action's name picks, such as "Left Half"; nil
    /// for a kind with no value, such as Fill (S-080).
    var builtInValueName: String? {
        guard case let .family(any) = self else { return nil }
        return switch any.value {
        case let place as PlaceAction: if case let .preset(preset) = place { preset.displayName } else { nil }
        case let resize as ResizeAction: if case let .step(step, _) = resize.change { step.displayName } else { nil }
        case let arrange as ArrangeAction: arrange.count.displayName
        case let focus as FocusAction: focus.target.displayName
        case let swap as SwapAction: swap.target.displayName
        default: nil
        }
    }

    /// How Settings names a built-in action: "Place Window: Left Half" (spec v11).
    var builtInDisplayName: String {
        builtInValueName.map { "\(displayName): \($0)" } ?? displayName
    }
}

extension BuiltInAction {
    /// One kind's built-in actions, as the Built In menu and the Help page list them.
    struct Group: Identifiable {
        let name: String
        let entries: [Entry]
        var id: String { name }
    }

    /// Built-in actions kind by kind, in alphabetical order (S-080, S-081).
    static var groups: [Group] {
        Dictionary(grouping: entries(), by: \.action.displayName)
            .map { Group(name: $0.key, entries: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension WindowScope {
    var displayName: String {
        switch self {
        case .all: "On Every Display"
        case .display: "On the Same Display"
        }
    }
}

extension ArrangeLayout {
    var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .columns: "Columns"
        case .rows: "Rows"
        }
    }
}

extension PlacePreset {
    var displayName: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .center: "Center"
        }
    }
}

extension WindowAnchor {
    /// For Move Window's Spot picker.
    var spotName: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom Right"
        }
    }

    /// For Resize Window's Keep in Place picker.
    var keepName: String {
        switch self {
        case .topLeft: "Top Left Corner"
        case .top: "Top Edge"
        case .topRight: "Top Right Corner"
        case .left: "Left Edge"
        case .center: "Center"
        case .right: "Right Edge"
        case .bottomLeft: "Bottom Left Corner"
        case .bottom: "Bottom Edge"
        case .bottomRight: "Bottom Right Corner"
        }
    }
}

// MARK: - Fields

/// A fraction shown as a percentage of the screen, clamped to `range`.
struct PercentRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void

    init(_ label: String, _ value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.range = range.lowerBound <= range.upperBound ? range : range.lowerBound...range.lowerBound
        self.set = set
    }

    var body: some View {
        NumberRow(label: label, unit: "%", spokenUnit: "percent of the screen",
                  value: Binding(get: { value * 100 }, set: { set(min(max($0 / 100, range.lowerBound), range.upperBound)) }))
    }
}

/// A number of points, either way.
struct PointsRow: View {
    let label: String
    let value: Double
    let set: (Double) -> Void

    init(_ label: String, _ value: Double, set: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.set = set
    }

    var body: some View {
        NumberRow(label: label, unit: "pt", spokenUnit: "points", value: Binding(get: { value }, set: { set($0.rounded()) }))
    }
}

struct NumberRow: View {
    let label: String
    let unit: String
    let spokenUnit: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: Space.sm) {
                TextField(label, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Layout.keyColumnWidth / 2)
                    .accessibilityLabel("\(label), \(spokenUnit)")
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

/// Grow and Shrink's widths as a list of percentages, applied on Return or
/// when focus leaves. Empty means the default list.
struct WidthsField: View {
    @Binding var widths: [Double]?
    @State private var text = ""
    @FocusState private var focused: Bool

    static func format(_ widths: [Double]) -> String {
        widths.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) }.joined(separator: ", ")
    }

    var body: some View {
        TextField("Widths", text: $text, prompt: Text(Self.format(ResizeAction.defaultWidths)))
            .focused($focused)
            .onSubmit(apply)
            .onChange(of: focused) { if !focused { apply() } }
            .onAppear { text = widths.map(Self.format) ?? "" }
            .onChange(of: widths) { if !focused { text = widths.map(Self.format) ?? "" } }
            .accessibilityLabel("Widths, percentages of the screen")
            .textEntry("Widths")
    }

    private func apply() {
        let parsed = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "%" })
            .compactMap { Double($0) }.filter { $0 > 0 && $0 <= 100 }.map { $0 / 100 }
        widths = parsed.isEmpty ? nil : parsed
        text = widths.map(Self.format) ?? ""
    }
}
