import Testing
@testable import UnnamedManagerKit

@Suite("Spaces settings (S-087)", .serialized)
struct SpacesSettingsTests {
    @Test("Both are on when unset; spans-displays says the opposite of its switch")
    func mapping() {
        #expect(SpacesSetting.rearrangeByRecentUse.isOn(stored: nil))
        #expect(SpacesSetting.separateSpaces.isOn(stored: nil))
        #expect(!SpacesSetting.rearrangeByRecentUse.isOn(stored: false))
        #expect(!SpacesSetting.separateSpaces.isOn(stored: true))
        #expect(SpacesSetting.rearrangeByRecentUse.stored(isOn: false) == false)
        #expect(SpacesSetting.separateSpaces.stored(isOn: true) == false)
    }

    @Test("Suggested: Rearrange off, Separate Spaces on")
    func suggestions() {
        #expect(!SpacesSetting.rearrangeByRecentUse.suggestedIsOn)
        #expect(SpacesSetting.separateSpaces.suggestedIsOn)
    }

    @Test("Writes and reads back the key in a test domain, never the real one")
    func roundTrip() {
        let prefs = SpacesPreferences(domainPrefix: "net.unnamed.manager.tests.")
        defer { SpacesSetting.allCases.forEach(prefs.remove) }
        #expect(prefs.domain(.rearrangeByRecentUse) == "net.unnamed.manager.tests.com.apple.dock")
        for setting in SpacesSetting.allCases {
            prefs.remove(setting)
            #expect(prefs.stored(setting) == nil)
            #expect(prefs.set(setting, isOn: false))
            #expect(prefs.stored(setting) == setting.stored(isOn: false))
            #expect(prefs.set(setting, isOn: true))
            #expect(prefs.isOn(setting))
        }
    }
}
