import Foundation
import Testing

/// The app's own text says Unnamed Manager (S-057). Only the code that
/// copies the Unnamed Launcher config (S-058) may name the old app.
@Suite("App name (S-057)")
struct AppNameTests {
    static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources", directoryHint: .isDirectory)

    @Test("No source file names Unnamed Launcher, except the config migration")
    func noOldName() throws {
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        let oldNames = ["Unnamed Launcher", "UnnamedLauncher", "unnamed-launcher", "net.unnamed.launcher"]
        for file in files where file.lastPathComponent != "LauncherMigration.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in oldNames {
                #expect(!text.contains(name), "\(file.lastPathComponent) still says \(name)")
            }
        }
    }
}
