import Foundation
import Testing
@testable import UnnamedManagerKit

/// What the action registry (S-060) must not change: the generated schema,
/// byte for byte, and how the writer lays out every valid spec fixture and
/// the starter config. The files in Golden/ were recorded before the
/// refactor. Delete one to record it again on purpose.
@Suite("Golden files (S-060)")
struct ActionGoldenTests {
    static let tests = URL(filePath: #filePath).deletingLastPathComponent()
    static let golden = tests.appending(path: "Golden", directoryHint: .isDirectory)
    static let fixtures = tests.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "spec/fixtures/valid", directoryHint: .isDirectory)

    /// Compares with the golden file, or records it when there is none.
    func matches(_ text: String, golden name: String) throws -> Bool {
        let url = Self.golden.appending(path: name)
        guard let recorded = try? String(contentsOf: url, encoding: .utf8) else {
            try FileManager.default.createDirectory(at: Self.golden, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        }
        return recorded == text
    }

    @Test("The schema is the same, byte for byte")
    func schema() throws {
        #expect(try matches(ConfigSchema.json, golden: "config.schema.json"))
    }

    @Test("The writer lays out the starter config the same way")
    func starter() throws {
        let document = try ConfigDocument(data: Data(ConfigLoader.starterJSON.utf8))
        #expect(try matches(String(decoding: document.data(), as: UTF8.self), golden: "written-starter.json"))
    }

    static let fixtureNames: [String] = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path(percentEncoded: false)))?
        .filter { $0.hasSuffix(".json") }.sorted() ?? []

    @Test("The writer lays out every valid spec fixture the same way", arguments: fixtureNames)
    func fixture(_ name: String) throws {
        let document = try ConfigDocument(data: Data(contentsOf: Self.fixtures.appending(path: name)))
        #expect(try matches(String(decoding: document.data(), as: UTF8.self), golden: "written-\(name)"))
    }
}
