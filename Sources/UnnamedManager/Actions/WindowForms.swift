import SwiftUI
import UnnamedManagerKit

extension MaximizeAction: EditableAction {
    @MainActor static func form(_ value: Binding<MaximizeAction>) -> some View {
        Section {
            Toggle("Press Again to Restore", isOn: value.toggle)
        } footer: {
            Text("Fills the screen without the menu bar and Dock. Not full screen.")
        }
    }
}
