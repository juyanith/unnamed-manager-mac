import Foundation
import Testing
@testable import UnnamedLauncherKit

/// Runs every fixture in the shared spec (`spec/`, a git submodule) that
/// applies to the Mac: valid ones must load with the listed warnings,
/// invalid ones must be rejected. ConfigIssue has no rule ids yet, so a
/// rule is checked through its subject where the manifest gives one.
@Suite("Shared spec fixtures")
struct SpecFixtureTests {
    struct Fixture: Decodable, Sendable, CustomTestStringConvertible {
        struct Issue: Decodable, Sendable {
            var rule: String
            var subject: String?
        }
        var file: String
        var valid: Bool
        var errors: [Issue]?
        var warnings: [Issue]?
        var platforms: [String]?
        var testDescription: String { file }
    }

    struct Manifest: Decodable {
        var fixtures: [Fixture]
    }

    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "spec/fixtures", directoryHint: .isDirectory)

    static let fixtures: [Fixture] = {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.fixtures.filter { $0.platforms?.contains("mac") ?? true }
    }()

    @Test("The spec submodule is checked out")
    func present() {
        #expect(!Self.fixtures.isEmpty, "No fixtures in \(Self.folder.path). Run git submodule update --init.")
    }

    @Test("Each fixture loads or is rejected as the spec says", arguments: fixtures)
    func fixture(_ fixture: Fixture) throws {
        let data = try Data(contentsOf: Self.folder.appending(path: fixture.file))
        switch ConfigLoader.load(data) {
        case let .success(loaded):
            #expect(fixture.valid, "Loaded, but the spec says it breaks \(fixture.errors?.first?.rule ?? "a rule").")
            let expected = Set((fixture.warnings ?? []).compactMap(\.subject))
            #expect(Set(loaded.warnings.compactMap(\.subject)) == expected)
        case let .failure(errors):
            #expect(!fixture.valid, "Rejected: \(errors.issues.map(\.message))")
            for error in fixture.errors ?? [] {
                guard let subject = error.subject else { continue }
                #expect(errors.issues.contains { $0.subject == subject },
                        "No issue about “\(subject)” for \(error.rule): \(errors.issues.map(\.message))")
            }
        }
    }
}
