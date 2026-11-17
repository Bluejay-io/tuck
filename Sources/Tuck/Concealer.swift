import Foundation

/// Hides other apps' menu bar items on macOS 27 through MenuBarAgent's assessment mode:
/// while an assertion is held, only the listed bundle IDs (and system items) stay on the bar.
@MainActor
final class Concealer {
    private static let framework = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configure = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activate = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidate = NSSelectorFromString("invalidate")

    private static let classes: (AnyClass, AnyClass)? = {
        guard dlopen(framework, RTLD_NOW) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
              let assertion = NSClassFromString("MBAssessmentModeAssertion"),
              configuration.instancesRespond(to: configure),
              assertion.instancesRespond(to: activate) else { return nil }
        return (configuration, assertion)
    }()

    static var isAvailable: Bool { classes != nil }

    private var current: NSObject?

    var isHiding: Bool { current != nil }

    /// Holds a new assertion allowing `bundleIDs`, then drops the previous one, so nothing flickers.
    func show(only bundleIDs: [String]) async throws {
        guard let (configurationClass, assertionClass) = Self.classes else {
            throw TuckError("MenuBarClientCore isn't available on this macOS")
        }
        let systemItems = (0...63).map { NSNumber(value: $0) } as NSArray
        guard let configuration = (configurationClass as! NSObject.Type).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
                .perform(Self.configure, with: systemItems, with: bundleIDs as NSArray)?.takeUnretainedValue(),
              let assertion = (assertionClass as! NSObject.Type).init() as NSObject? else {
            throw TuckError("Couldn't create the assertion")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var done = false
            let completion: @convention(block) (Any?) -> Void = { error in
                DispatchQueue.main.async {
                    guard !done else { return }
                    done = true
                    if let error { continuation.resume(throwing: TuckError("MenuBarAgent refused: \(error)")) } else { continuation.resume() }
                }
            }
            _ = assertion.perform(Self.activate, with: configuration, with: completion)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard !done else { return }
                done = true
                continuation.resume(throwing: TuckError("MenuBarAgent didn't answer in 3s"))
            }
        }
        let previous = current
        current = assertion
        _ = previous?.perform(Self.invalidate)
    }

    func showAll() {
        _ = current?.perform(Self.invalidate)
        current = nil
    }
}

struct TuckError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
