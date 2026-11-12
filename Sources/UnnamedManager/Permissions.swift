import AppKit
import ApplicationServices
import CoreGraphics

/// The two permissions the app needs to capture keys (S-002). Apple's
/// names, as the glossary says.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility = "Accessibility"
    case inputMonitoring = "Input Monitoring"

    var id: String { rawValue }

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: CGPreflightListenEventAccess()
        }
    }

    /// Asks macOS to list the app in the pane and, the first time, show its
    /// prompt. Then opens the pane itself.
    func openSettings() {
        switch self {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
        NSWorkspace.shared.open(settingsURL)
    }

    private var settingsURL: URL {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    static var missing: [Permission] { allCases.filter { !$0.isGranted } }
}
