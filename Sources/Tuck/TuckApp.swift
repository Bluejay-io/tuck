import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private let lab = Lab()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let autosave = "TuckDivider"
        if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(autosave)") == nil {
            UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position \(autosave)")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = autosave
        lab.ownFrame = { [weak self] in self?.statusItem.button?.window?.frame }
        statusItem.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Tuck")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showWindow)

        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Tuck test"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: LabView(lab: lab))
        window.center()
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lab.showAll()
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
