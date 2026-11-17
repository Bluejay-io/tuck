import AppKit
import ApplicationServices

struct MenuBarApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let pid: pid_t
    let itemCount: Int
    var id: String { bundleID }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum MenuBarScanner {
    static let menuBarAgent = "com.apple.MenuBarAgent"

    static func scan() -> (apps: [MenuBarApp], systemItems: [String]) {
        var apps: [MenuBarApp] = []
        var system: [String] = []
        let own = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, app.processIdentifier != own else { continue }
            let items = extras(of: app.processIdentifier)
            guard !items.isEmpty else { continue }
            if bundleID == menuBarAgent {
                system = items.map { string($0, kAXIdentifierAttribute) ?? string($0, kAXDescriptionAttribute) ?? "?" }
                continue
            }
            apps.append(MenuBarApp(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: app.processIdentifier, itemCount: items.count))
        }
        return (apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, system)
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

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
