import SwiftUI

/// The Settings window (Settings…, ⌘,): your bindings, actions and
/// contexts, and the preferences, a toolbar tab each, as in Xcode's Key
/// Bindings and Mail's Rules (DESIGN.md, Archetype; S-085).
struct SettingsWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
        .onChange(of: model.store.revision) { model.editor.reloadFromStore() }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openWelcome: { openWindow(id: WindowID.welcome) })
        }
    }

    /// A tab's page. The editor tabs fill a window you can resize; the
    /// others are a Form that fits its content.
    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general, .windows:
            SettingsForm(tab: tab)
        case .bindings:
            BindingsPage().editorTab()
        case .actions:
            ActionsPage().editorTab()
        case .contexts:
            ContextsPage().editorTab()
        }
    }
}

private extension View {
    func editorTab() -> some View {
        frame(minWidth: Layout.editorTabMin.width, maxWidth: .infinity,
              minHeight: Layout.editorTabMin.height, maxHeight: .infinity)
            .background(EditorTabWindow())
    }
}

/// Makes the Settings window resizable while an editor tab shows, at the
/// size you left it, as Xcode's Key Bindings tab does. A Settings window
/// fits each tab and can't be resized on its own; the Form tabs keep that.
private struct EditorTabWindow: NSViewRepresentable {
    /// The window's size on the editor tabs when you left them last,
    /// shared by all three.
    @MainActor static var size = Layout.editorTabDefault

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        private weak var resized: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                resized = window
                // After SwiftUI has sized the window to the tab, which it
                // animates when you switch tabs.
                Task { @MainActor in
                    try? await Task.sleep(for: Motion.tabResize)
                    window.styleMask.insert(.resizable)
                    let size = EditorTabWindow.size
                    let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - size.height)
                    window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
                }
            } else if let resized {
                // Leaving for a Form tab.
                EditorTabWindow.size = resized.frame.size
                resized.styleMask.remove(.resizable)
                self.resized = nil
            }
        }
    }
}
