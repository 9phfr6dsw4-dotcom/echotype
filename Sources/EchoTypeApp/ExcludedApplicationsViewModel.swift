import AppKit
import EchoTypeCore
import Foundation
import Observation

@MainActor
@Observable
final class ExcludedApplicationsViewModel {
    private(set) var policy: ExcludedAppPolicy
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    static let defaultsKey = "EchoType.excludedAppPolicy"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(ExcludedAppPolicy.self, from: data) {
            self.policy = saved
        } else {
            self.policy = ExcludedAppPolicy()
        }
    }

    func addApplication(at url: URL) {
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "EchoType could not read an app bundle identifier from that application."
            return
        }
        let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? url.deletingPathExtension().lastPathComponent
        policy.addUserExclusion(bundleIdentifier: bundleIdentifier, displayName: displayName)
        persist()
        errorMessage = nil
    }

    func removeApplication(bundleIdentifier: String) {
        policy.removeUserExclusion(bundleIdentifier: bundleIdentifier)
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(policy), forKey: Self.defaultsKey)
        } catch {
            errorMessage = "Could not save excluded apps: \(error.localizedDescription)"
        }
    }
}
