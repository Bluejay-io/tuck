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
    private var observers: [NSObjectProtocol] = []

    init() {
        tucked = Set(UserDefaults.standard.stringArray(forKey: "tucked") ?? [])
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkTrust() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.apply()
                    try? await Task.sleep(for: .seconds(2))
                    self?.rescan()
                }
            })
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
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).subtracting(tucked)
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

    func showEverything() {
        concealer.showAll()
    }

    /// Opens a tucked app's own menu. Pressing it through Accessibility works while it stays
    /// hidden; when that fails, the app is shown for a moment and pressed where it appears.
    func open(_ app: MenuBarApp) async {
        try? await Task.sleep(for: .milliseconds(120))
        for _ in 0..<2 {
            if let item = MenuBarScanner.extras(of: app.pid).first,
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await lift(app)
    }

    private func lift(_ app: MenuBarApp) async {
        lifted = app.bundleID
        await apply()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if let item = MenuBarScanner.extras(of: app.pid).first, (MenuBarScanner.frame(item)?.width ?? 0) > 0,
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { break }
        }
        let started = Date()
        liftMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] _ in
            guard Date().timeIntervalSince(started) > 0.5 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self?.dropLift()
            }
        }
    }

    private func dropLift() {
        if let liftMonitor { NSEvent.removeMonitor(liftMonitor) }
        liftMonitor = nil
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
