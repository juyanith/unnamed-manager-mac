import Foundation
import Testing
@testable import UnnamedManagerKit

@Suite("Quit on Close (S-086, spec v16)")
struct QuitOnCloseTests {
    let on = Config.Windows(quitOnClose: true)
    let preview = QuitOnClose.App(bundleIds: ["com.apple.Preview"])

    @Test("Off by default, read and written as windows.quitOnClose")
    func setting() throws {
        let plain = try ConfigLoader.load(Data((FocusHistoryTests.minimal + " }").utf8)).get()
        #expect(!plain.config.windows.quitOnClose)
        let set = try ConfigLoader.load(Data((FocusHistoryTests.minimal + #", "windows": { "quitOnClose": true, "apps": { "com.apple.Preview": { "quit": false } } } }"#).utf8)).get()
        #expect(set.config.windows.quitOnClose)
        #expect(set.config.windows.apps["com.apple.Preview"] == .init(quit: false))
        #expect(ConfigWriter.write(set.config, actionOrder: []).contains(
            #""windows": { "quitOnClose": true, "apps": { "com.apple.Preview": { "focus": true, "swap": true, "arrange": true, "quit": false } } }"#))
    }

    @Test("A quitOnClose or quit that isn't a boolean is wrong-type")
    func rejected() {
        #expect(FocusHistoryTests().rule(#""quitOnClose": "yes""#) == .wrongType)
        #expect(FocusHistoryTests().rule(#""apps": { "com.apple.Preview": { "quit": 0 } }"#) == .wrongType)
    }

    @Test("Quits an app whose last window closed, only with the setting on")
    func quits() {
        #expect(QuitOnClose.shouldQuit(preview, settings: on, own: nil))
        #expect(!QuitOnClose.shouldQuit(preview, settings: Config.Windows(), own: nil))
    }

    @Test("Keeps Finder, this app, and apps with quit false, also when the app is inside one")
    func kept() {
        #expect(!QuitOnClose.shouldQuit(.init(bundleIds: ["com.apple.finder"]), settings: on, own: nil))
        #expect(!QuitOnClose.shouldQuit(.init(bundleIds: ["net.unnamed.manager"]), settings: on, own: "net.unnamed.manager"))
        var excluded = on
        excluded.apps = ["com.apple.Preview": .init(quit: false), "com.apple.Notes": .init(arrange: false)]
        #expect(!QuitOnClose.shouldQuit(preview, settings: excluded, own: nil))
        #expect(QuitOnClose.shouldQuit(.init(bundleIds: ["com.apple.Notes"]), settings: excluded, own: nil))
        #expect(!QuitOnClose.shouldQuit(.init(bundleIds: ["com.example.helper", "com.apple.Preview"]), settings: excluded, own: nil))
        excluded.apps = ["com.apple.finder": .init()]
        #expect(!QuitOnClose.shouldQuit(.init(bundleIds: ["com.apple.finder"]), settings: excluded, own: nil))
        #expect(!QuitOnClose.canQuit("com.apple.finder") && QuitOnClose.canQuit("com.apple.Preview"))
    }

    @Test("Keeps an app with a window left, one that never showed one, a hidden app, and a menu bar app")
    func notYet() {
        var app = preview
        app.windows = 1
        #expect(!QuitOnClose.shouldQuit(app, settings: on, own: nil))
        app = preview
        app.hadWindow = false
        #expect(!QuitOnClose.shouldQuit(app, settings: on, own: nil))
        app = preview
        app.isHidden = true
        #expect(!QuitOnClose.shouldQuit(app, settings: on, own: nil))
        app = preview
        app.isBackground = true
        #expect(!QuitOnClose.shouldQuit(app, settings: on, own: nil))
    }
}

extension QuitOnCloseTests {
    @Test("A helper app is inside the apps around it, innermost first")
    func containing() {
        let helper = URL(filePath: "/Applications/Big.app/Contents/Frameworks/Kit.app/Contents/Helpers/Helper.app")
        #expect(QuitOnClose.containingApps(of: helper).map(\.lastPathComponent) == ["Kit.app", "Big.app"])
        #expect(QuitOnClose.containingApps(of: URL(filePath: "/Applications/Preview.app")).isEmpty)
    }
}
