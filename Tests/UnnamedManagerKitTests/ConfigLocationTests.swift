import Foundation
import Testing
@testable import UnnamedManagerKit

private let home = URL(fileURLWithPath: "/Users/someone")

@Test("The default config file is under ~/.config")
func defaultLocation() {
    let url = ConfigLocation.url(environment: [:], home: home)
    #expect(url.path == "/Users/someone/.config/unnamed-manager/config.json")
    #expect(!ConfigLocation.isOverridden(environment: [:]))
}

@Test("APP_STORE overrides the config file", arguments: [
    (["APP_STORE": "/tmp/test.json"], "/tmp/test.json", true),
    (["APP_STORE": ""], "/Users/someone/.config/unnamed-manager/config.json", false),
])
func override(_ env: [String: String], expected: String, overridden: Bool) {
    #expect(ConfigLocation.url(environment: env, home: home).path == expected)
    #expect(ConfigLocation.isOverridden(environment: env) == overridden)
}
