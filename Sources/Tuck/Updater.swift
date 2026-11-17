import Foundation

@MainActor
final class Updater: ObservableObject {
    @Published private(set) var available: String?
    @Published private(set) var installing = false
    @Published private(set) var checkedAt: Date?

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    private var timer: Timer?
    private static let installCommand = "curl -fsSL https://raw.githubusercontent.com/bluejay-io/tuck/main/install.sh | bash"

    func start() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    func check() async {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/bluejay-io/tuck/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("Tuck/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tag = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String else { return }
        checkedAt = Date()
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        available = Self.isNewer(latest, than: current) ? latest : nil
    }

    func install() {
        guard !installing else { return }
        installing = true
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tuck-update.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", Self.installCommand]
        process.standardInput = FileHandle.nullDevice
        let handle = try? FileHandle(forWritingTo: log)
        process.standardOutput = handle ?? FileHandle.nullDevice
        process.standardError = handle ?? FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.installing = false }
        }
        do { try process.run() } catch { installing = false }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
