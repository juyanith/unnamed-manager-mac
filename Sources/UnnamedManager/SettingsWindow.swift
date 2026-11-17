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
                    .modifier(SameSize())
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .background(ResizableWindow(model: model))
        .noInitialFocus()
        .onChange(of: model.store.revision) { model.editor.reloadFromStore() }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openWelcome: { openWindow(id: WindowID.welcome) })
        }
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general, .windows: SettingsForm(tab: tab)
        case .bindings: BindingsPage()
        case .actions: ActionsPage()
        case .contexts: ContextsPage()
        }
    }
}

/// Every tab has the window's size, so switching tabs never resizes it.
/// A Settings window sizes itself to each tab; with each tab's ideal size
/// the window's own, there's nothing to change.
private struct SameSize: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.frame(minWidth: Layout.settingsMin.width, idealWidth: model.settingsSize.width, maxWidth: .infinity,
                      minHeight: Layout.settingsMin.height, idealHeight: model.settingsSize.height, maxHeight: .infinity)
    }
}

/// Makes the Settings window resizable, which a Settings window isn't on
/// its own, and keeps the size you give it in the model for every tab.
private struct ResizableWindow: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> Probe { Probe(model: model) }
    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        let model: AppModel

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            // SwiftUI opens it at the smallest width; give it the size you left it at.
            DispatchQueue.main.async { [model] in
                // The page sits below the toolbar, which the frame includes.
                let toolbar = window.frame.height - window.contentLayoutRect.height
                let size = CGSize(width: model.settingsSize.width, height: model.settingsSize.height + toolbar)
                window.setFrame(NSRect(origin: NSPoint(x: window.frame.minX, y: window.frame.maxY - size.height), size: size),
                                display: true)
                Self.makeResizable(window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(didResize),
                                                   name: NSWindow.didEndLiveResizeNotification, object: window)
            // SwiftUI takes the resizable flag away again as it lays out.
            NotificationCenter.default.addObserver(self, selector: #selector(didUpdate),
                                                   name: NSWindow.didUpdateNotification, object: window)
        }

        private static func makeResizable(_ window: NSWindow) {
            if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
        }

        @objc private func didUpdate(_ note: Notification) {
            if let window { Self.makeResizable(window) }
        }

        @objc private func didResize(_ note: Notification) {
            guard let window else { return }
            model.settingsSize = window.contentLayoutRect.size
        }
    }
}
