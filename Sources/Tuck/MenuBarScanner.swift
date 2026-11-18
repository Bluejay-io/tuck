import AppKit
import ApplicationServices

struct MenuBarApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let pid: pid_t
    let bundleURL: URL?
    var id: String { bundleID }

    var icon: NSImage {
        if let bundleURL { return NSWorkspace.shared.icon(forFile: bundleURL.path) }
        return NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }

    /// macOS 27 only keeps apps visible while hiding when they run from /Applications or /System.
    var canStayVisible: Bool {
        guard let path = bundleURL?.path else { return true }
        return path.hasPrefix("/Applications/") || path.hasPrefix("/System/")
    }
}

enum MenuBarScanner {
    static let menuBarAgent = "com.apple.MenuBarAgent"

    /// Running apps that own at least one menu bar item, Tuck and the system's own excluded.
    static func scan() -> [MenuBarApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app -> MenuBarApp? in
            guard let bundleID = app.bundleIdentifier, app.processIdentifier != own, bundleID != menuBarAgent,
                  bundleID != Bundle.main.bundleIdentifier,
                  !extras(of: app.processIdentifier).isEmpty else { return nil }
            return MenuBarApp(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: app.processIdentifier, bundleURL: app.bundleURL)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func extras(of pid: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success else { return [] }
        return (children as? [AXUIElement]) ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}
