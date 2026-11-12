import AppKit
import SwiftUI
import UnnamedManagerKit

/// A field that records a key (S-025). For a leader it takes a full chord;
/// for a key inside a menu, one key with no modifiers. Escape stops
/// recording without a change, except for a leader, which may use it.
struct KeyRecorder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    let path: KeySequence
    @State private var problem: String?
    @State private var monitor: Any?

    private var editor: BindingsEditor { model.editor }
    private var isRecording: Bool { editor.recording == path }
    private var current: Chord { path.lastStep ?? path.leader }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                isRecording ? editor.stopRecording() : editor.startRecording(path)
            } label: {
                HStack(spacing: Space.sm) {
                    if isRecording {
                        Text(path.isLeader ? "Press a chord…" : "Press a key…")
                            .foregroundStyle(.secondary)
                    } else {
                        Keycap(label: current.description)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                        .foregroundStyle(isRecording ? Palette.accentText : .secondary)
                }
                .frame(minWidth: Layout.keyRecorderWidth, alignment: .leading)
            }
            .help(isRecording ? "Press the key to use, or Escape to stop" : "Record a new key (Space)")
            .accessibilityLabel(isRecording ? "Recording a key" : "Key, \(current.description)")
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: isRecording, initial: true) { _, recording in
            recording ? startMonitor() : stopMonitor()
        }
        .onDisappear {
            stopMonitor()
            if isRecording { editor.stopRecording() }
        }
    }

    private func startMonitor() {
        problem = nil
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func record(_ event: NSEvent) {
        guard let key = KeyName(keyCode: event.keyCode) else {
            problem = "That key can't be used. Try a letter, digit, function key or Space."
            return
        }
        let modifiers = Modifiers(event.modifierFlags)
        if key == .escape && modifiers.isEmpty && !path.isLeader {
            editor.stopRecording()
            return
        }
        let chord = Chord(modifiers: modifiers, key: key)
        if let problem = editor.setKey(path, chord, undo: undo) {
            self.problem = problem
        } else {
            problem = nil
            editor.stopRecording()
        }
    }
}

extension Modifiers {
    /// The four chord modifiers in an NSEvent's flags.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
