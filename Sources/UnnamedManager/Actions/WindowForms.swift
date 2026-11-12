import SwiftUI
import UnnamedManagerKit

// The forms for the window actions (S-070). Numbers are clamped as they're
// typed, so a form never makes a file the spec rejects.

extension MinimizeAction: EditableAction {
    @MainActor static func form(_ value: Binding<MinimizeAction>) -> some View {
        Section {
            Text("Sends the window in front to the Dock, as ⌘M does.")
                .foregroundStyle(.secondary)
        }
    }
}

extension MaximizeAction: EditableAction {
    @MainActor static func form(_ value: Binding<MaximizeAction>) -> some View {
        Section {
            Toggle("Press Again to Restore", isOn: value.toggle)
        } footer: {
            Text("Fills the screen without the menu bar and Dock. Not full screen.")
        }
    }
}

extension FocusAction: EditableAction {
    @MainActor static func form(_ value: Binding<FocusAction>) -> some View {
        Section {
            Picker("Direction", selection: value.direction) {
                ForEach(FocusDirection.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } footer: {
            Text("Left, Right, Up and Down go to the nearest window that way, on any display. Next Window and Previous Window go through windows by display, then top to bottom.")
        }
    }
}

extension PlaceAction: EditableAction {
    @MainActor static func form(_ value: Binding<PlaceAction>) -> some View {
        let frame = value.wrappedValue.fractions
        func set(_ change: (inout FractionFrame) -> Void) {
            var new = value.wrappedValue.fractions
            change(&new)
            value.wrappedValue = .frame(new)
        }
        return Section {
            Picker("Preset", selection: Binding<PlacePreset?>(
                get: { if case let .preset(preset) = value.wrappedValue { preset } else { nil } },
                set: { value.wrappedValue = $0.map(PlaceAction.preset) ?? .frame(frame) })) {
                ForEach(PlacePreset.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                Divider()
                Text("Custom").tag(PlacePreset?.none)
            }
            PercentRow("X", frame.x, range: 0...(1 - frame.width)) { new in set { $0.x = new } }
            PercentRow("Y", frame.y, range: 0...(1 - frame.height)) { new in set { $0.y = new } }
            PercentRow("Width", frame.width, range: 0.01...(1 - frame.x)) { new in set { $0.width = new } }
            PercentRow("Height", frame.height, range: 0.01...(1 - frame.y)) { new in set { $0.height = new } }
        } footer: {
            Text("Parts of the screen without the menu bar and Dock. Change a number to place the window your own way.")
        }
    }
}

extension MoveAction: EditableAction {
    @MainActor static func form(_ value: Binding<MoveAction>) -> some View {
        Section {
            Picker("Move", selection: Binding(
                get: { if case .to = value.wrappedValue { 0 } else { 1 } },
                set: { value.wrappedValue = $0 == 0 ? .to(x: 0.5, y: 0.5) : .by(dx: 40, dy: 0) })) {
                Text("To a Spot").tag(0)
                Text("By Points").tag(1)
            }
            switch value.wrappedValue {
            case let .to(x, y):
                Picker("Spot", selection: Binding<WindowAnchor?>(
                    get: { WindowAnchor.allCases.first { $0.unit == (CGFloat(x), CGFloat(y)) } },
                    set: { if let spot = $0 { value.wrappedValue = .to(x: Double(spot.unit.0), y: Double(spot.unit.1)) } })) {
                    ForEach(WindowAnchor.allCases, id: \.self) { Text($0.spotName).tag(Optional($0)) }
                    Divider()
                    Text("Custom").tag(WindowAnchor?.none)
                }
                PercentRow("X", x, range: 0...1) { value.wrappedValue = .to(x: $0, y: y) }
                PercentRow("Y", y, range: 0...1) { value.wrappedValue = .to(x: x, y: $0) }
            case let .by(dx, dy):
                PointsRow("Right", dx) { value.wrappedValue = .by(dx: $0, dy: dy) }
                PointsRow("Down", dy) { value.wrappedValue = .by(dx: dx, dy: $0) }
            }
        } footer: {
            if case .to = value.wrappedValue {
                Text("0 % is the left or top edge, 50 % centered, 100 % the right or bottom edge. The size stays the same.")
            } else {
                Text("Negative numbers move left or up. At least part of the title bar always stays on the screen.")
            }
        }
    }
}

extension ResizeAction: EditableAction {
    /// The Resize picker's choices.
    private enum Mode: Hashable { case grow, shrink, to, by }

    @MainActor static func form(_ value: Binding<ResizeAction>) -> some View {
        let action = value.wrappedValue
        let mode: Mode = switch action.change {
        case .step(.grow, _): .grow
        case .step(.shrink, _): .shrink
        case .to: .to
        case .by: .by
        }
        let widths: [Double]? = if case let .step(_, widths) = action.change { widths } else { nil }
        return Section {
            Picker("Resize", selection: Binding(get: { mode }, set: { new in
                let change: Change = switch new {
                case .grow: .step(.grow, widths: widths)
                case .shrink: .step(.shrink, widths: widths)
                case .to: .to(width: 0.5, height: 0.5) // grid: ok fractions of the screen, not layout
                case .by: .by(dw: 80, dh: 60)
                }
                value.wrappedValue = ResizeAction(change, anchor: action.anchor)
            })) {
                Text("Grow Through Widths").tag(Mode.grow)
                Text("Shrink Through Widths").tag(Mode.shrink)
                Text("To a Size").tag(Mode.to)
                Text("By Points").tag(Mode.by)
            }
            switch action.change {
            case let .step(step, widths):
                WidthsField(widths: Binding(get: { widths }, set: { value.wrappedValue.change = .step(step, widths: $0) }))
            case let .to(width, height):
                PercentRow("Width", width, range: 0.01...1) { value.wrappedValue.change = .to(width: $0, height: height) }
                PercentRow("Height", height, range: 0.01...1) { value.wrappedValue.change = .to(width: width, height: $0) }
                anchorPicker(value)
            case let .by(dw, dh):
                PointsRow("Wider", dw) { value.wrappedValue.change = .by(dw: $0, dh: dh) }
                PointsRow("Taller", dh) { value.wrappedValue.change = .by(dw: dw, dh: $0) }
                anchorPicker(value)
            }
        } footer: {
            switch mode {
            case .grow, .shrink:
                Text("Steps the width to the next one in the list, keeping the left edge. Percentages of the screen without the menu bar and Dock.")
            case .to:
                Text("Percentages of the screen without the menu bar and Dock.")
            case .by:
                Text("Negative numbers make the window narrower or shorter. It never grows past the screen.")
            }
        }
    }

    @MainActor private static func anchorPicker(_ value: Binding<ResizeAction>) -> some View {
        Picker("Keep in Place", selection: value.anchor) {
            ForEach(WindowAnchor.allCases, id: \.self) { Text($0.keepName).tag($0) }
        }
    }
}
