import SwiftUI
import UnnamedManagerKit

/// An entry's icon as the Guide and the Bindings editor draw it (S-054 to
/// S-056): SF Symbols and the app's glyph in secondary, so colored app and
/// file icons stand out; empty space when there's none, so titles line up.
struct EntryIcon: View {
    let source: IconSource?
    /// The Guide only reads icons looked up when the config loaded. The
    /// editor looks up what you type.
    var looksUp = false
    /// nil hides the icon from VoiceOver, as in the Guide, where the row's
    /// label names it.
    var accessibilityName: String?

    var body: some View {
        let image = source.flatMap { looksUp ? GuideIcons.shared.lookUpIcon(for: $0) : GuideIcons.shared.icon(for: $0) }
        Group {
            switch (source, image) {
            case let (.symbol(name), .some):
                Image(systemName: name)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            case let (.menu, .some(glyph)):
                Image(nsImage: glyph)
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
            case let (_, .some(icon)):
                Image(nsImage: icon).resizable()
            default:
                Color.clear
            }
        }
        .frame(width: Layout.guideIconSize, height: Layout.guideIconSize)
        .accessibilityHidden(accessibilityName == nil || image == nil)
        .accessibilityLabel(accessibilityName ?? "")
    }
}
