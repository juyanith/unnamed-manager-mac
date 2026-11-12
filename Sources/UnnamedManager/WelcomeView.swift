import SwiftUI
import UnnamedManagerKit

/// Where first-run setup stands (S-040), worked out from plain values so
/// the self-test can check it.
struct WelcomeStatus: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var ranSequence: Bool

    /// The window shows until all three are done.
    var isComplete: Bool { accessibility && inputMonitoring && ranSequence }

    init(accessibility: Bool, inputMonitoring: Bool, ranSequence: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.ranSequence = ranSequence
    }

    init(launcher: Launcher) {
        self.init(accessibility: !launcher.missingPermissions.contains(.accessibility),
                  inputMonitoring: !launcher.missingPermissions.contains(.inputMonitoring),
                  ranSequence: launcher.hasRunSequence)
    }
}

/// The first-run window (S-040): what the app does, the two permissions,
/// and the first leader to try. Not a tour: three steps with check marks.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let status = WelcomeStatus(launcher: model.launcher)
        let leader = model.store.loaded?.leaders.first(where: \.isMenu)
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.md) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Space.section * 2, height: Space.section * 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Welcome to Unnamed Manager").font(.title2)
                    Text("Press a leader chord, then one key per menu, to open apps, run commands and send shortcuts.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Space.md) {
                step(1, "Turn on Accessibility", done: status.accessibility) {
                    Button("Open Settings…") { Permission.accessibility.openSettings() }
                }
                step(2, "Turn on Input Monitoring", done: status.inputMonitoring) {
                    Button("Open Settings…") { Permission.inputMonitoring.openSettings() }
                }
                step(3, "Try \(leader?.path.description ?? "your leader")", done: status.ranSequence) {
                    Text(leader.map { "Then press a key from its \($0.title) menu." } ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text("Your bindings are in")
                    Text(model.store.url.path(percentEncoded: false).replacingOccurrences(of: URL.homeDirectory.path(percentEncoded: false), with: "~/"))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Open Config File") { model.store.openFile() }
                Button(status.isComplete ? "Done" : "Later") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.margin)
        .frame(width: Layout.welcomeWidth)
        .fixedSize(horizontal: false, vertical: true)
        .noInitialFocus()
    }

    private func step(_ number: Int, _ title: String, done: Bool, @ViewBuilder detail: () -> some View) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Palette.accentText : .secondary)
                .frame(width: Space.xxl)
                .accessibilityLabel(done ? "Done" : "Step \(number)")
            Text(title).font(.headline)
            Spacer()
            if !done { detail() }
        }
        .accessibilityElement(children: .combine)
    }
}
