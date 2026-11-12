import AppKit
import Carbon.HIToolbox
import UnnamedManagerKit

/// Ties the parts together: permissions, the event tap, the sequence
/// engine, the Guide and the actions (M1). The menu bar menu reads its state.
@Observable
final class Launcher {
    let store: ConfigStore
    private(set) var missingPermissions: [Permission] = Permission.missing
    /// Both permissions are granted but macOS still refused the tap.
    private(set) var needsRelaunch = false
    /// True while another app has Secure Event Input on, as password
    /// fields do, so no keys reach the tap (S-038).
    private(set) var secureInputIsOn = false

    /// True once any binding has run, ever (S-040, the welcome window).
    private(set) var hasRunSequence = UserDefaults.standard.bool(forKey: "ranSequence")

    /// The last failed action, for the log and the Guide (S-015).
    private(set) var lastFailure: String?

    /// Enabled in the menu bar menu (S-009). Remembered across launches.
    var isEnabled: Bool = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            if !Store.isOverridden { UserDefaults.standard.set(isEnabled, forKey: "enabled") }
            updateCapture()
        }
    }

    /// The engine runs on the tap thread; effects come back to the main queue.
    @ObservationIgnored private let engine = EngineBox()
    @ObservationIgnored private lazy var capture = KeyCapture { [engine, weak self] event in
        let output = engine.handle(event)
        if let effect = output.effect {
            // The main queue keeps effects in order: show, then run.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(effect) } }
        }
        return output.consume
    }
    @ObservationIgnored let guide = GuideController()
    @ObservationIgnored var runner = ActionRunner()
    /// When the Guide shows, times out and flashes (S-016 to S-018, S-021).
    @ObservationIgnored private(set) var schedule = GuideSchedule(runtime: .init(), ui: .init())
    @ObservationIgnored private var scheduleTimer: Task<Void, Never>?
    @ObservationIgnored private var permissionTimer: Timer?
    /// False in snapshots and the self-test, which never touch the keyboard.
    @ObservationIgnored private var capturesKeys = false

    init(store: ConfigStore) {
        self.store = store
        store.onLoad = { [unowned self] config in
            engine.replace(config)
            GuideIcons.shared.load(config.iconSources())
            schedule = GuideSchedule(runtime: config.config.runtime, ui: config.config.ui)
            guide.position = GuidePlacement.Position(rawValue: config.config.ui.position.lowercased()) ?? .center
            guide.theme = config.config.ui.theme
            scheduleTimer?.cancel()
            guide.hide()
        }
    }

    /// Lets every key through while the Bindings window records a key.
    func setRecording(_ recording: Bool) {
        engine.setPaused(recording)
        if recording { guide.hide() }
    }

    /// True while leaders are being captured.
    var isCapturing: Bool { capture.isRunning }

    /// Loads the config and starts capturing. Snapshots and the self-test
    /// pass `captureKeys: false`, so they never touch the real keyboard.
    func start(captureKeys: Bool, seed: String? = nil) {
        store.start(seed: seed)
        capturesKeys = captureKeys
        guard captureKeys else { return }
        updateCapture()
        // Grants happen in System Settings, so look again every two seconds
        // until both are in, and whenever the app becomes active.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        // Context Aware needs the app in front at the moment a leader is pressed (S-013).
        engine.setFrontApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [engine] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            engine.setFrontApp(app?.bundleIdentifier)
        }
    }

    func refreshPermissions() {
        let missing = Permission.missing
        if missing != missingPermissions { missingPermissions = missing }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputIsOn { secureInputIsOn = secure }
        updateCapture()
    }

    private func updateCapture() {
        guard capturesKeys else { return }
        if isEnabled && missingPermissions.isEmpty {
            let started = capture.start()
            if needsRelaunch == started { needsRelaunch = !started }
        } else {
            capture.stop()
            engine.reset()
            guide.hide()
            if needsRelaunch { needsRelaunch = false }
        }
    }

    /// Quits and opens a fresh copy, for grants that need a relaunch.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// For the self-test, which can't turn Secure Event Input on.
    func setSecureInputForTesting(_ on: Bool) {
        secureInputIsOn = on
    }

    /// Removes the tap before quitting (S-009).
    func stop() {
        capture.stop()
    }

    // MARK: - Events

    /// Shows a failed action in the Guide and writes it to the log (S-015).
    func report(_ message: String, title: String) {
        lastFailure = message
        log.error("Action “\(title, privacy: .public)” failed: \(message, privacy: .public)")
        // With the Guide turned off, failures go to the log only (S-021).
        if store.loaded?.config.runtime.showHud ?? true { guide.showFailure(message, title: title) }
    }

    /// Milliseconds on a clock that never jumps, for the schedule.
    private static var nowMs: Double { ProcessInfo.processInfo.systemUptime * 1_000 }

    /// Feeds one engine effect to the schedule, then runs the action if any.
    func apply(_ effect: SequenceEffect) {
        perform(schedule.handle(effect, at: Self.nowMs))
        armScheduleTimer()
        guard let config = store.loaded, case let .run(binding, frontApp) = effect else { return }
        if !hasRunSequence {
            hasRunSequence = true
            if !Store.isOverridden { UserDefaults.standard.set(true, forKey: "ranSequence") }
        }
        guard let id = binding.action, let chosen = config.config.actions[id],
              let action = ContextResolver.resolve(chosen, frontApp: frontApp, contexts: config.config.contexts)
        else { return }
        Task {
            do throws(PlanError) {
                try await runner.run(action, id: id)
            } catch {
                report(error.message, title: binding.title)
            }
        }
    }

    private func perform(_ commands: [GuideCommand]) {
        for command in commands {
            switch command {
            case let .show(menu, path, frontApp):
                guard let config = store.loaded else { continue }
                guide.show(GuideContent(menu: menu, path: path, config: config, frontApp: frontApp))
            case let .showHome(home, path, frontApp):
                guard let config = store.loaded else { continue }
                guide.show(GuideContent(home: home, path: path, config: config, frontApp: frontApp))
            case .hide:
                guide.hide()
            case .flash:
                guide.flash()
            case .bell:
                NSSound.beep()
            case .endSequence:
                engine.reset()
            }
        }
    }

    /// One timer, for whichever comes first: the delay or the timeout.
    private func armScheduleTimer() {
        scheduleTimer?.cancel()
        guard let deadline = schedule.nextDeadline else { return }
        let wait = max(0, deadline - Self.nowMs)
        scheduleTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(wait))
            guard !Task.isCancelled, let self else { return }
            perform(schedule.tick(at: Self.nowMs))
            armScheduleTimer()
        }
    }
}
