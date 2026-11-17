import AppKit
import ServiceManagement
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--reset") {
            try? SMAppService.mainApp.unregister()
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            print("Tuck: removed launch at login and settings")
            exit(0)
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = TuckStore()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let autosave = "TuckDivider"
        if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(autosave)") == nil {
            UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position \(autosave)")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = autosave
        statusItem.button?.image = Self.glyph
        statusItem.button?.setAccessibilityLabel("Tuck")
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        store.rescan()
        if store.onboarded {
            Task { await store.apply() }
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.showEverything()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.rescan()
        menu.removeAllItems()

        if !store.trusted || !store.onboarded {
            menu.addItem(item("Finish setting up Tuck…", #selector(openOnboarding)))
        } else if store.tuckedApps.isEmpty {
            let empty = NSMenuItem(title: "Nothing tucked yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            menu.addItem(item("Choose apps to tuck…", #selector(openSettings)))
        } else {
            menu.addItem(NSMenuItem.sectionHeader(title: "Tucked away"))
            for app in store.tuckedApps {
                let open = item(app.name, #selector(openApp(_:)))
                open.image = icon(for: app)
                open.representedObject = app.bundleID
                menu.addItem(open)

                let untuck = item("Move \(app.name) inline", #selector(untuck(_:)))
                untuck.image = icon(for: app)
                untuck.representedObject = app.bundleID
                untuck.keyEquivalentModifierMask = .option
                untuck.isAlternate = true
                menu.addItem(untuck)
            }
        }

        menu.addItem(.separator())
        let settings = item("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = item("Quit Tuck", #selector(NSApplication.terminate(_:)))
        quit.target = NSApp
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func icon(for app: MenuBarApp) -> NSImage {
        let image = app.icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let app = store.apps.first(where: { $0.bundleID == id }) else { return }
        Task { await store.open(app) }
    }

    @objc private func untuck(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.setTucked(id, false)
    }

    // MARK: Windows

    @objc private func openOnboarding() { showOnboarding() }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Welcome to Tuck", root: OnboardingView(store: store) { [weak self] in
                self?.finishOnboarding()
            })
        }
        present(onboardingWindow)
    }

    private func finishOnboarding() {
        store.onboarded = true
        UserDefaults.standard.set(0, forKey: "onboardingStep")
        if !UserDefaults.standard.bool(forKey: "didSetUpLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "didSetUpLaunchAtLogin")
            store.launchAtLogin = true
        }
        onboardingWindow?.close()
        onboardingWindow = nil
        Task { await store.apply() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Tuck Settings", root: SettingsView(store: store))
        }
        present(settingsWindow)
    }

    private func makeWindow<Content: View>(title: String, root: Content) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The menu bar glyph: three tiles tucked into a pocket, drawn as a template image.
    private static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for (x, y, angle) in [(3.6, 9.6, 12.0), (7.4, 10.4, -4.0), (11.2, 9.6, -14.0)] as [(CGFloat, CGFloat, CGFloat)] {
                let tile = NSBezierPath(roundedRect: NSRect(x: -1.8, y: -1.8, width: 3.6, height: 3.6), xRadius: 1, yRadius: 1)
                var transform = AffineTransform(translationByX: x + 1.8, byY: y + 1.8)
                transform.rotate(byDegrees: angle)
                tile.transform(using: transform)
                tile.fill()
            }
            let pocket = NSBezierPath()
            pocket.move(to: NSPoint(x: 2, y: 11))
            pocket.line(to: NSPoint(x: 16, y: 11))
            pocket.line(to: NSPoint(x: 16, y: 6))
            pocket.curve(to: NSPoint(x: 9, y: 2.5), controlPoint1: NSPoint(x: 16, y: 3.4), controlPoint2: NSPoint(x: 13, y: 2.5))
            pocket.curve(to: NSPoint(x: 2, y: 6), controlPoint1: NSPoint(x: 5, y: 2.5), controlPoint2: NSPoint(x: 2, y: 3.4))
            pocket.close()
            pocket.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
