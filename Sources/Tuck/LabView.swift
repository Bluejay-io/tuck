import AppKit
import SwiftUI

@MainActor
final class Lab: ObservableObject {
    @Published var trusted = PermissionGuide.isTrusted
    @Published var apps: [MenuBarApp] = []
    @Published var systemItems: [String] = []
    @Published var tucked: Set<String> = []
    @Published var hiding = false
    @Published var log: [String] = []
    let concealer = Concealer()
    var ownFrame: () -> NSRect? = { nil }
    private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TuckLab.log")

    init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = PermissionGuide.isTrusted
                if now != self.trusted {
                    self.trusted = now
                    self.note("Accessibility trusted: \(now)")
                    if now { self.scan() }
                }
            }
        }
        note("Started. macOS \(ProcessInfo.processInfo.operatingSystemVersionString). Assessment API available: \(Concealer.isAvailable). Trusted: \(trusted). Bundle: \(Bundle.main.bundlePath)")
        if trusted { scan() }
    }

    func note(_ line: String) {
        let stamped = "\(Date().formatted(date: .omitted, time: .standard))  \(line)"
        log.insert(stamped, at: 0)
        let data = Data((stamped + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    func scan() {
        let result = MenuBarScanner.scan()
        if !hiding { apps = result.apps }
        systemItems = result.systemItems
        let positions = result.apps.map { app -> String in
            let x = MenuBarScanner.extras(of: app.pid).first.flatMap(MenuBarScanner.frame).map { Int($0.minX) } ?? -1
            return "\(app.name)@\(x)"
        }
        note("Scan: [\(positions.joined(separator: ", "))]; Tuck@\(MenuBarScanner.extras(of: ProcessInfo.processInfo.processIdentifier).first.flatMap(MenuBarScanner.frame).map { Int($0.minX) } ?? -1); system items: \(result.systemItems)")
    }

    private var allowed: [String] {
        [Bundle.main.bundleIdentifier ?? ""] + apps.map(\.bundleID).filter { !tucked.contains($0) }
    }

    func applyHiding() async {
        do {
            try await concealer.show(only: allowed)
            hiding = true
            note("Hiding \(tucked.sorted()); allowed \(allowed)")
        } catch {
            note("Hide failed: \(error.localizedDescription)")
        }
    }

    func showAll() {
        concealer.showAll()
        hiding = false
        note("Showing everything")
    }

    func pressWhileHidden(_ app: MenuBarApp) {
        let items = MenuBarScanner.extras(of: app.pid)
        guard let item = items.first else { return note("\(app.name): no AX items found while hidden") }
        let frame = MenuBarScanner.frame(item).map { "\($0)" } ?? "none"
        let actions = MenuBarScanner.actions(item)
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        note("\(app.name): AXPress while hidden -> \(result.rawValue) (frame \(frame), actions \(actions))")
    }

    func liftAndPress(_ app: MenuBarApp) async {
        do {
            try await concealer.show(only: allowed + [app.bundleID])
            note("\(app.name): lifted")
            var pressed = false
            for attempt in 0..<30 {
                try await Task.sleep(for: .milliseconds(100))
                if let item = MenuBarScanner.extras(of: app.pid).first, let frame = MenuBarScanner.frame(item), frame.width > 0 {
                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    note("\(app.name): AXPress after lift (\(attempt * 100 + 100) ms) -> \(result.rawValue), frame \(frame)")
                    pressed = true
                    break
                }
            }
            if !pressed { note("\(app.name): item never appeared after lift") }
        } catch {
            note("\(app.name): lift failed: \(error.localizedDescription)")
        }
    }

    func rehide() async {
        await applyHiding()
    }
}

struct LabView: View {
    @ObservedObject var lab: Lab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tuck test").font(.system(size: 18, weight: .semibold))
            HStack {
                Label(lab.trusted ? "Accessibility allowed" : "Accessibility not allowed yet",
                      systemImage: lab.trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(lab.trusted ? .green : .orange)
                Spacer()
                if !lab.trusted {
                    Button("Allow Accessibility…") { PermissionGuide.shared.show() }.buttonStyle(.borderedProminent)
                }
            }
            Divider()
            HStack {
                Text("Menu bar apps").font(.headline)
                Spacer()
                Button("Rescan") { lab.scan() }.disabled(!lab.trusted)
            }
            List(lab.apps) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    VStack(alignment: .leading) {
                        Text(app.name)
                        Text("\(app.bundleID) · \(app.itemCount) item\(app.itemCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if lab.hiding && lab.tucked.contains(app.bundleID) {
                        Button("Open (hidden)") { lab.pressWhileHidden(app) }
                        Button("Open (lift)") { Task { await lab.liftAndPress(app) } }
                    }
                    Toggle("Tuck", isOn: Binding(get: { lab.tucked.contains(app.bundleID) }, set: { on in
                        if on { lab.tucked.insert(app.bundleID) } else { lab.tucked.remove(app.bundleID) }
                    }))
                    .disabled(lab.hiding)
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button(lab.hiding ? "Re-hide" : "Hide tucked apps") { Task { await lab.applyHiding() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!lab.trusted || lab.tucked.isEmpty)
                Button("Show everything") { lab.showAll() }.disabled(!lab.hiding)
                Spacer()
                Text("Assessment API: \(Concealer.isAvailable ? "available" : "missing")").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Log").font(.headline)
            ScrollView {
                Text(lab.log.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 140)
        }
        .padding(20)
        .frame(width: 640, height: 660)
    }
}
