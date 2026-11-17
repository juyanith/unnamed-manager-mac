import SwiftUI

/// A key in a small rounded rectangle: "E", "Space", "esc". Used in the
/// Guide's rows and footer (DESIGN-SYSTEM.md, Components).
struct Keycap: View {
    let label: String
    var font: Font = .system(.callout, design: .monospaced).weight(.medium)

    var body: some View {
        Text(label)
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs / 2)
            .frame(minWidth: Layout.keycapMinWidth)
            .background(Surfaces.keycap, in: .rect(cornerRadius: Radius.xs))
            .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(Surfaces.keycapStroke))
    }
}

extension View {
    /// Left-aligns a text field in a grouped Form, where text fields are
    /// right-aligned by default. A right-aligned field doesn't draw trailing
    /// spaces, so a typed space looks like nothing happened until the next
    /// letter. Use it on every field people type words into; numbers stay
    /// right-aligned (DESIGN-SYSTEM.md, Components).
    ///
    /// A grouped Form ignores the alignment of a text field it lays out
    /// itself, so the field goes into a LabeledContent with its own label
    /// hidden. Put focus and submit modifiers before this one, on the field.
    func textEntry(_ label: LocalizedStringKey) -> some View {
        LabeledContent(label) {
            labelsHidden().multilineTextAlignment(.leading)
        }
    }
}

/// The add and remove buttons under a list on a Settings tab, where the
/// toolbar holds the tabs, as in Mail's Rules (DESIGN-SYSTEM.md, Components).
/// Icon-only borderless buttons, each with a name for VoiceOver and its help.
struct ListBar<Buttons: View>: View {
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Space.xs) {
                buttons
                Spacer()
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
        }
    }
}
