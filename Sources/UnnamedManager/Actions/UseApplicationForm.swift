import AppKit
import SwiftUI
import UnnamedManagerKit

extension UseApplicationAction: EditableAction {
    @MainActor static func form(_ value: Binding<UseApplicationAction>) -> some View {
        Section {
            TextField("Bundle ID", text: value.bundleId)
                .textEntry("Bundle ID")
            Button("Choose App…") { chooseApp(value) }
            Picker("Mode", selection: value.mode) {
                ForEach(Config.AppMode.menuOrder, id: \.self) { Text($0.displayName).tag($0) }
            }
        } footer: {
            Text(value.wrappedValue.mode.explanation)
        }
    }

    /// An Open panel limited to apps (S-030).
    @MainActor private static func chooseApp(_ value: Binding<UseApplicationAction>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        value.wrappedValue.bundleId = id
    }
}
