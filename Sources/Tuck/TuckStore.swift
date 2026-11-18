import AppKit
import ServiceManagement

@MainActor
final class TuckStore: ObservableObject {
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var apps: [MenuBarApp] = []
    @Published private(set) var tucked: Set<String>
    @Published private(set) var lastError: String?

    private let concealer = Concealer()
    private var lifted: String?
    private var liftMonitor: Any?
    private var liftGeneration = 0
    private var runningObserver: NSKeyValueObservation?
    private var allowedRunning: Set<String> = []

    init() {
        tucked = Set(UserDefaults.standard.stringArray(forKey: "tucked") ?? [])
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkTrust() }
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        runningObserver = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, Self.runningBundleIDs() != self.allowedRunning else { return }
                await self.apply()
                try? await Task.sleep(for: .seconds(2))
                self.rescan()
            }
        }
    }

    var onboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded"); objectWillChange.send() }
    }

    var tuckedApps: [MenuBarApp] { apps.filter { tucked.contains($0.bundleID) } }

    /// Every app Tuck should list: running menu bar apps, plus tucked ones it remembers are hidden.
    func rescan() {
        guard trusted else { return }
        apps = MenuBarScanner.scan()
    }

    func isTucked(_ bundleID: String) -> Bool { tucked.contains(bundleID) }

    func setTucked(_ bundleID: String, _ on: Bool) {
        if on { tucked.insert(bundleID) } else { tucked.remove(bundleID) }
        UserDefaults.standard.set(Array(tucked), forKey: "tucked")
        Task { await apply() }
    }

    /// Hides tucked apps by allowing every other running app on the bar.
    func apply() async {
        guard trusted, onboarded, !tucked.isEmpty else {
            concealer.showAll()
            return
        }
        let running = Self.runningBundleIDs()
        allowedRunning = running
        var allowed = running.subtracting(tucked)
        allowed.insert(Bundle.main.bundleIdentifier ?? "io.bluejay.tuck")
        if let lifted { allowed.insert(lifted) }
        do {
            try await concealer.show(only: Array(allowed))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("Tuck: hiding failed: \(error.localizedDescription)")
        }
    }

    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func showEverything() {
        concealer.showAll()
    }

    /// Opens a tucked app's own menu: the app is shown on the bar for a moment and pressed where
    /// it appears, so its menu anchors under its icon instead of at a hidden item's zero frame.
    /// An app that can't be shown is pressed while hidden instead.
    func open(_ app: MenuBarApp) async {
        removeLiftMonitor()
        liftGeneration += 1
        let generation = liftGeneration
        try? await Task.sleep(for: .milliseconds(120))
        lifted = app.bundleID
        await apply()
        var pressed = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            guard generation == liftGeneration else { return }
            if let item = MenuBarScanner.extras(of: app.pid).first, (MenuBarScanner.frame(item)?.width ?? 0) > 0,
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                pressed = true
                break
            }
        }
        guard pressed else {
            if let item = MenuBarScanner.extras(of: app.pid).first {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
            }
            return dropLift()
        }
        let started = Date()
        liftMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] _ in
            guard Date().timeIntervalSince(started) > 0.5 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, generation == self.liftGeneration else { return }
                self.dropLift()
            }
        }
    }

    private func removeLiftMonitor() {
        if let liftMonitor { NSEvent.removeMonitor(liftMonitor) }
        liftMonitor = nil
    }

    private func dropLift() {
        removeLiftMonitor()
        lifted = nil
        Task { await apply() }
    }

    private func checkTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        if now {
            rescan()
            Task { await apply() }
        } else {
            concealer.showAll()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Tuck: launch at login failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
