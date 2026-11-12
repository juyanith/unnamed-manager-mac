import AppKit
import SwiftUI
import UnnamedManagerKit

extension OpenAction: EditableAction {
    @MainActor static func form(_ value: Binding<OpenAction>) -> some View {
        Section {
            TextField("File, Folder or URL", text: value.target)
                .textEntry("File, Folder or URL")
            Button("Choose…") { chooseFile(value) }
        } footer: {
            Text("A path starting with / or ~, or a URL such as https://example.com.")
        }
    }

    @MainActor private static func chooseFile(_ value: Binding<OpenAction>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        let home = ActionPlanner.expandTilde("~", home: .homeDirectory)
        value.wrappedValue.target = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension RunCommandAction: EditableAction {
    @MainActor static func form(_ value: Binding<RunCommandAction>) -> some View {
        Section {
            TextField("Command", text: Binding(
                get: { value.wrappedValue.command.joined(separator: "\n") },
                set: { value.wrappedValue.command = $0.split(separator: "\n").map(String.init) }),
                      axis: .vertical)
                .lineLimit(2...6)
                .textEntry("Command")
            TextField("Folder", text: Binding(
                get: { value.wrappedValue.cwd ?? "" },
                set: { value.wrappedValue.cwd = $0.isEmpty ? nil : $0 }),
                      prompt: Text("~"))
                .textEntry("Folder")
        } footer: {
            Text("One argument per line, the program first. It runs with no shell, so nothing is expanded except a leading ~.")
        }
    }
}

extension SendShortcutAction: EditableAction {
    @MainActor static func form(_ value: Binding<SendShortcutAction>) -> some View {
        Section {
            TextField("Keys", text: value.keys, prompt: Text("Cmd+F"))
                .textEntry("Keys")
        } footer: {
            Text("One or more chords separated by spaces, such as Cmd+K S.")
        }
    }
}
