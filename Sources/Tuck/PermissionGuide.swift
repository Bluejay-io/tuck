import AppKit
import ApplicationServices

/// Opens System Settings at the Accessibility list and docks a small panel under it holding
/// Tuck's icon, ready to drag into the list. Closes itself once Tuck is trusted.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var timer: Timer?
    private var lastAnchor: CGRect?
    var isDragging = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static var listName: String {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
            ? "Device Control and Data Access" : "Accessibility"
    }

    func show() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        if panel == nil { panel = makePanel() }
        position()
        panel?.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Clears a stale Accessibility entry (one left by an older build) and starts over.
    func fix() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "io.bluejay.tuck"]
        try? reset.run()
        reset.waitUntilExit()
        show()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func tick() {
        if Self.isTrusted {
            close()
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" {
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        position()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 92),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.material = .popover
        content.state = .active
        let tile = DragTile(frame: NSRect(x: 14, y: 16, width: 180, height: 60), bundleURL: Bundle.main.bundleURL)
        let label = NSTextField(wrappingLabelWithString: "Drag Tuck into \(Self.listName), then switch it on.")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 206, y: 22, width: 200, height: 48)
        content.addSubview(tile)
        content.addSubview(label)
        panel.contentView = content
        return panel
    }

    /// Docks under the System Settings window when there is one, else at the bottom of the screen.
    private func position() {
        guard let panel, let screen = NSScreen.main, !isDragging else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let settings = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerName as String] as? String == "System Settings",
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 300, rect.height > 200 else { return nil }
            return rect
        }.max { $0.width * $0.height < $1.width * $1.height }
        if let lastAnchor, lastAnchor == settings ?? .zero, panel.isVisible { return }
        lastAnchor = settings ?? .zero
        var origin: NSPoint
        if let settings {
            let appKitY = primaryHeight - settings.maxY
            origin = NSPoint(x: settings.midX - panel.frame.width / 2, y: appKitY - panel.frame.height - 10)
        } else {
            origin = NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.minY + 40)
        }
        origin.y = max(origin.y, screen.visibleFrame.minY + 8)
        panel.setFrameOrigin(origin)
    }
}

private final class DragTile: NSView, NSDraggingSource {
    private let bundleURL: URL
    private let icon: NSImage
    private let name: String

    init(frame: NSRect, bundleURL: URL) {
        self.bundleURL = bundleURL
        icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        name = FileManager.default.displayName(atPath: bundleURL.path).replacingOccurrences(of: ".app", with: "")
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: NSRect(x: 10, y: 10, width: 40, height: 40))
        (name as NSString).draw(at: NSPoint(x: 60, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        ("Drag me" as NSString).draw(at: NSPoint(x: 60, y: 13), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(NSRect(x: 10, y: 10, width: 40, height: 40), contents: icon)
        PermissionGuide.shared.isDragging = true
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        PermissionGuide.shared.isDragging = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
