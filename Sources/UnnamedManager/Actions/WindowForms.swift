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

extension FillAction: EditableAction {
    @MainActor static func form(_ value: Binding<FillAction>) -> some View {
        Section {
            Toggle("Press Again to Restore", isOn: value.toggle)
        } footer: {
            Text("Fills the screen without the menu bar and Dock, less the gap from Settings. Not full screen.")
        }
    }
}

extension ArrangeAction: EditableAction {
    @MainActor static func form(_ value: Binding<ArrangeAction>) -> some View {
        let action = value.wrappedValue
        // A number of windows can't have more groups than windows.
        let mostGroups = if case let .windows(number) = action.count { number } else { ArrangeAction.groupsRange.upperBound }
        return Section {
            Picker("Windows", selection: Binding(get: { action.count }, set: { new in
                value.wrappedValue.count = new
                if case let .windows(number) = new, let groups = action.groups, groups > number { value.wrappedValue.groups = number }
            })) {
                ForEach(Array(ArrangeAction.countRange), id: \.self) { Text(ArrangeCount.windows($0).displayName).tag(ArrangeCount.windows($0)) }
                Divider()
                Text(ArrangeCount.all.displayName).tag(ArrangeCount.all)
            }
            Picker("Groups", selection: value.groups) {
                Text("Automatic").tag(Int?.none)
                Divider()
                ForEach(Array(1...mostGroups), id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            Picker("Layout", selection: value.layout) {
                ForEach(ArrangeLayout.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } footer: {
            Text("Arranges the window in front and the ones you used before it, on its display, in columns or rows of equal size, with the gap from the Windows tab. Windows keep their order from left to right. When the windows don't fill the grid evenly, the window in front stays in the column or row it's in and takes the spare room there. Automatic groups go up to Maximum Columns and Maximum Rows on the Windows tab, and an automatic layout is columns on a wide display and rows on a tall one.")
        }
    }
}

extension FocusAction: EditableAction {
    @MainActor static func form(_ value: Binding<FocusAction>) -> some View {
        Section {
            TargetRows(label: "Focus On", target: value.target)
            scopePicker(value.scope)
        } footer: {
            Text("Left, Right, Up and Down go to the nearest window you can see that way. Next Window and Previous Window go through the windows you can see in rows, as you read, display by display. First Window, Last Window and numbers count in that order. Windows hidden behind others are skipped. Window Used Before goes back to the window you used before this one, even behind others or on another Space, so pressing again comes back. On the Same Display keeps to the display of the window in front. With no window there, you hear the alert sound.")
        }
    }
}

extension SwapAction: EditableAction {
    @MainActor static func form(_ value: Binding<SwapAction>) -> some View {
        Section {
            TargetRows(label: "Swap With", target: value.target)
            scopePicker(value.scope)
        } footer: {
            Text("The window in front trades place and size with that window, and keeps focus. Left, Right, Up and Down pick the nearest window you can see that way. The others, and numbers, count the windows you can see in rows, as you read, display by display, as Focus Window does. Window Used Before is the window you used before this one, even behind others, on this Space; pressing again swaps them back. With no window there, nothing moves and you hear the alert sound.")
        }
    }
}

extension SpaceSendAction: EditableAction {
    /// The picker's choices: a side, or a number set below it.
    private enum Choice: Hashable { case side(SpaceDirection), number }

    @MainActor static func form(_ value: Binding<SpaceSendAction>) -> some View {
        Section {
            Picker("Send To", selection: Binding<Choice>(
                get: { if case let .side(direction) = value.wrappedValue.target { .side(direction) } else { .number } },
                set: { new in
                    switch new {
                    case let .side(direction): value.wrappedValue.target = .side(direction)
                    case .number: if case .side = value.wrappedValue.target { value.wrappedValue.target = .number(1) }
                    }
                })) {
                ForEach(SpaceDirection.allCases, id: \.self) { Text("Space to the \($0.displayName)").tag(Choice.side($0)) }
                Divider()
                Text("Space Number").tag(Choice.number)
            }
            if case let .number(number) = value.wrappedValue.target {
                LabeledContent("Number") {
                    HStack(spacing: Space.sm) {
                        Text("\(number)").monospacedDigit()
                        Stepper("Space number", value: Binding(get: { number }, set: { value.wrappedValue.target = .number(max(1, $0)) }),
                                in: 1...16)
                            .labelsHidden()
                            .accessibilityValue("\(number)")
                    }
                }
            }
            Toggle("Go With the Window", isOn: value.follow)
        } footer: {
            Text("Puts the window in front on another Space of its display. Numbers count Spaces as Mission Control shows them, without full-screen apps. With Go With the Window off, you stay, and the window you used before here takes focus. If macOS won't move the window quietly, Unnamed Manager holds its title bar and presses the Switch to Desktop shortcut, which must be on in Keyboard Shortcuts.")
        }
    }
}

/// Focus Window's and Swap Window's target: a picker of the words and
/// Window Number, with a Number stepper below it for a number (spec v10, v11).
private struct TargetRows: View {
    /// The picker's choices: a word, or a number set below it.
    private enum Choice: Hashable { case window(FocusDirection), number }

    let label: String
    @Binding var target: WindowTarget

    var body: some View {
        Picker(label, selection: Binding<Choice>(
            get: { if case let .window(direction) = target { .window(direction) } else { .number } },
            set: { new in
                switch new {
                case let .window(direction): target = .window(direction)
                case .number: if case .window = target { target = .number(1) }
                }
            })) {
            ForEach(FocusDirection.allCases, id: \.self) { Text($0.displayName).tag(Choice.window($0)) }
            Divider()
            Text("Window Number").tag(Choice.number)
        }
        if case let .number(number) = target {
            LabeledContent("Number") {
                HStack(spacing: Space.sm) {
                    Text("\(number)").monospacedDigit()
                    Stepper("Window number", value: Binding(get: { number }, set: { target = .number(max(1, $0)) }), in: 1...99)
                        .labelsHidden()
                        .accessibilityValue("\(number)")
                }
            }
        }
    }
}

/// Focus Window's and Swap Window's Windows picker (spec v10).
@MainActor private func scopePicker(_ scope: Binding<WindowScope>) -> some View {
    Picker("Windows", selection: scope) {
        ForEach(WindowScope.allCases, id: \.self) { Text($0.displayName).tag($0) }
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
                Text(ResizeStep.grow.displayName).tag(Mode.grow)
                Text(ResizeStep.shrink.displayName).tag(Mode.shrink)
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

extension SpaceSwitchAction: EditableAction {
    @MainActor static func form(_ value: Binding<SpaceSwitchAction>) -> some View {
        Section {
            Picker("Direction", selection: value.target) {
                ForEach(SpaceDirection.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } footer: {
            Text("Goes to the Space to the left or right on the display of the window in front, without the slide. Full-screen apps count as Spaces. With no window in front, nothing happens. If a macOS update brings the slide back, Control-Left and Control-Right still work.")
        }
    }
}
