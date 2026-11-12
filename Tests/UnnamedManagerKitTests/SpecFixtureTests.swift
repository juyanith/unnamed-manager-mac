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

    /// Spec v2 fixtures for window actions the app doesn't have yet, with
    /// the story that builds each. A pending fixture must still fail, so
    /// one that starts passing fails the test until it's taken off here.
    static let pending: [String: String] = [
        "valid/window-actions.json": "S-062 to S-069",
        "invalid/window-preset-and-frame.json": "S-064",
        "invalid/window-frame-past-edge.json": "S-064",
        "invalid/window-bad-preset.json": "S-064",
        "invalid/window-place-neither.json": "S-064",
        "invalid/window-frame-missing-height.json": "S-064",
        "invalid/window-empty-widths.json": "S-065",
        "invalid/window-bad-step.json": "S-065",
        "invalid/window-to-and-by.json": "S-066",
        "invalid/window-fraction-range.json": "S-066",
        "invalid/window-anchor-with-step.json": "S-067",
        "invalid/window-widths-without-step.json": "S-067",
        "invalid/window-zero-size.json": "S-067",
        "invalid/window-bad-anchor.json": "S-067",
        "invalid/window-resize-none.json": "S-067",
        "invalid/window-bad-direction.json": "S-068",
        "invalid/window-focus-no-direction.json": "S-068",
    ]

    @Test("Every pending fixture is in the manifest")
    func pendingExist() {
        #expect(Set(Self.pending.keys).subtracting(Self.fixtures.map(\.file)).isEmpty)
    }

    @Test("The spec submodule is checked out")
    func present() {
        #expect(!Self.fixtures.isEmpty, "No fixtures in \(Self.folder.path). Run git submodule update --init.")
    }

    @Test("Each fixture loads or is rejected as the spec says", arguments: fixtures)
    func fixture(_ fixture: Fixture) throws {
        if let story = Self.pending[fixture.file] {
            try withKnownIssue("Pending until \(story)") { try check(fixture) }
        } else {
            try check(fixture)
        }
    }

    private func check(_ fixture: Fixture) throws {
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

/// Each family's part of the generated schema is the spec's, so the two
/// schemas can't drift (spec v2).
@Suite("Schema against the spec")
struct SpecSchemaTests {
    static func variants(_ json: Data) throws -> [String: NSDictionary] {
        let root = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let defs = try #require(root["$defs"] as? [String: Any])
        let action = try #require(defs["action"] as? [String: Any])
        let list = try #require(action["oneOf"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: list.compactMap { variant in
            guard let properties = variant["properties"] as? [String: Any],
                  let type = (properties["type"] as? [String: Any])?["enum"] as? [String],
                  let name = type.first else { return nil }
            return (name, variant as NSDictionary)
        })
    }

    @Test("Every kind the app has is described as the spec describes it", arguments: ActionRegistry.standard.kinds)
    func matches(_ kind: ActionKind) throws {
        let spec = try Self.variants(Data(contentsOf: SpecFixtureTests.folder.deletingLastPathComponent().appending(path: "config.schema.json")))
        let app = try Self.variants(Data(ConfigSchema.json.utf8))
        let expected = try #require(spec[kind.type], "The spec's schema has no \(kind.type).")
        #expect(app[kind.type] == expected)
    }
}
