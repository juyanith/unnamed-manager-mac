import Foundation
import Testing
@testable import UnnamedManagerKit

/// Runs every fixture in the shared spec (`spec/`, a git submodule) that
/// applies to the Mac: valid ones must load with the listed warnings,
/// invalid ones must be rejected for the rule the manifest names (S-059).
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
            let expected = Set((fixture.warnings ?? []).map { "\($0.rule) \($0.subject ?? "")" })
            #expect(Set(loaded.warnings.map { "\($0.rule?.rawValue ?? "none") \($0.subject ?? "")" }) == expected)
        case let .failure(errors):
            #expect(!fixture.valid, "Rejected: \(errors.issues.map(\.message))")
            for error in fixture.errors ?? [] {
                #expect(errors.issues.contains { $0.rule?.rawValue == error.rule && (error.subject == nil || $0.subject == error.subject) },
                        "No \(error.rule) issue\(error.subject.map { " about “\($0)”" } ?? ""): \(errors.issues.map { "\($0.rule?.rawValue ?? "none"): \($0.message)" })")
            }
        }
    }

    @Test("The app's rules are exactly the spec's rule ids")
    func ruleIDs() throws {
        let spec = try String(contentsOf: Self.folder.deletingLastPathComponent().appending(path: "CONFIG-SPEC.md"), encoding: .utf8)
        let validation = spec.components(separatedBy: "## Validation").dropFirst().first?
            .components(separatedBy: "\n## ").first ?? ""
        let ids = Set(validation.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("| `") else { return nil }
            return line.dropFirst(3).split(separator: "`").first.map(String.init)
        })
        #expect(ids == Set(ConfigRule.allCases.map(\.rawValue)))
    }
}
