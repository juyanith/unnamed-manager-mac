import Foundation
import UnnamedManagerKit

extension SelfTest {
    /// S-058: copying the old app's config in place of the starter, on
    /// throwaway files in /tmp.
    static func migrationChecks(_ model: AppModel) async {
        let home = URL(fileURLWithPath: "/Users/someone")
        check("S-058 tests never read the real old config",
              LauncherMigration.sourceURL(environment: ["APP_STORE": "/tmp/x.json"], home: home) == nil)
        check("S-058 APP_LAUNCHER_STORE names the old config in tests",
              LauncherMigration.sourceURL(environment: ["APP_STORE": "/tmp/x.json", "APP_LAUNCHER_STORE": "/tmp/old.json"],
                                          home: home)?.path == "/tmp/old.json")
        let real = LauncherMigration.sourceURL(environment: [:], home: home)
        check("S-058 the old config is in its own folder under ~/.config",
              real?.path.hasPrefix("/Users/someone/.config/") == true
              && real != ConfigLocation.url(environment: [:], home: home))

        let starter = Data(ConfigLoader.starterJSON.utf8)
        check("S-058 the offer needs a new, unchanged starter and an old config",
              LauncherMigration.shouldOffer(createdStarter: true, current: starter, sourceExists: true)
              && !LauncherMigration.shouldOffer(createdStarter: false, current: starter, sourceExists: true)
              && !LauncherMigration.shouldOffer(createdStarter: true, current: Data("{}".utf8), sourceExists: true)
              && !LauncherMigration.shouldOffer(createdStarter: true, current: starter, sourceExists: false))

        let dir = URL(fileURLWithPath: "/tmp/UnnamedManager-migration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appending(path: "old/config.json")
        try? FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oldData = Data(SeedData.fixtureJSON.utf8)
        try? oldData.write(to: old)
        let oldDate = try? FileManager.default.attributesOfItem(atPath: old.path)[.modificationDate] as? Date

        // A first launch: the starter is written, then Copy Config replaces it.
        let fresh = ConfigStore(url: dir.appending(path: "fresh/config.json"))
        fresh.start()
        let migration = LauncherMigration(store: fresh, source: old)
        migration.start()
        check("S-058 a first launch with an old config offers Copy Config", migration.state == .offer)
        migration.copy()
        check("S-058 Copy Config copies the old config and loads it",
              migration.state == .copied && (try? Data(contentsOf: fresh.url)) == oldData
              && fresh.errors.isEmpty && fresh.loaded?.leaders.count == (try? ConfigLoader.load(oldData).get())?.leaders.count)
        let newDate = try? FileManager.default.attributesOfItem(atPath: old.path)[.modificationDate] as? Date
        check("S-058 the old config is never changed", (try? Data(contentsOf: old)) == oldData && oldDate == newDate)
        check("S-058 after copying, the menu says the config loaded, not created", !fresh.createdStarter)
        check("S-058 Welcome says where the config came from",
              LauncherMigration.Words.copied(migration.sourceDisplayPath).hasSuffix(old.path))

        // No old config: the starter, as before, and no offer.
        let alone = ConfigStore(url: dir.appending(path: "alone/config.json"))
        alone.start()
        let noSource = LauncherMigration(store: alone, source: dir.appending(path: "missing/config.json"))
        noSource.start()
        check("S-058 with no old config, the starter is written and nothing is offered",
              alone.createdStarter && noSource.state == .hidden)

        // A config of yours already exists: never offered, never overwritten.
        let mine = dir.appending(path: "mine/config.json")
        try? FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mineData = Data(#"{ "version": 1, "entries": [{ "keys": "Hyper+T", "title": "T", "action": "n" }], "actions": { "n": { "type": "noop" } } }"#.utf8)
        try? mineData.write(to: mine)
        let existing = ConfigStore(url: mine)
        existing.start()
        let keep = LauncherMigration(store: existing, source: old)
        keep.start()
        keep.copy()
        check("S-058 an existing config is never offered or overwritten",
              keep.state == .hidden && (try? Data(contentsOf: mine)) == mineData)

        // The starter was edited after launch: Copy Config leaves it alone.
        let edited = ConfigStore(url: dir.appending(path: "edited/config.json"))
        edited.start()
        let late = LauncherMigration(store: edited, source: old)
        late.start()
        try? mineData.write(to: edited.url)
        late.copy()
        check("S-058 a starter edited since launch is kept, and the offer goes",
              late.state == .hidden && (try? Data(contentsOf: edited.url)) == mineData)

        // The old app running: a warning badge and a section in the menu.
        let running = MenuBarStatus(launcher: model.launcher, store: model.store, otherAppRunning: true)
        check("S-058 the old app running puts the warning badge on the menu bar icon",
              !model.launcher.isEnabled || running.icon == .warning)
    }
}
