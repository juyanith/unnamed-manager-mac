import SwiftUI
import UnnamedManagerKit

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
