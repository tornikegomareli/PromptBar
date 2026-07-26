import Foundation
import Observation

/// Persisted preferences (PRD §22 P0 + §15). Backed by `UserDefaults` in the
/// application container. Observable so Settings reflects changes immediately.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let defaultProfile = "defaultProfile"
        static let defaultStyle = "defaultStyle"
        static let historyEnabled = "historyEnabled"
        static let retention = "historyRetention"
        static let excludedApps = "excludedApps"
        static let selectionPopup = "selectionPopupEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _defaultProfile = defaults.string(forKey: Key.defaultProfile).flatMap(TargetProfile.init) ?? .auto
        _defaultStyle = defaults.string(forKey: Key.defaultStyle).flatMap(SuggestionStyle.init) ?? .balanced
        _historyEnabled = defaults.bool(forKey: Key.historyEnabled)
        _retention = defaults.string(forKey: Key.retention).flatMap(RetentionPolicy.init) ?? .month
        _excludedApps = Self.decode([ExcludedApp].self, from: defaults.data(forKey: Key.excludedApps)) ?? []
        _selectionPopupEnabled = defaults.bool(forKey: Key.selectionPopup)
        _launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Stored preferences

    private var _defaultProfile: TargetProfile
    var defaultProfile: TargetProfile {
        get { _defaultProfile }
        set { _defaultProfile = newValue; defaults.set(newValue.rawValue, forKey: Key.defaultProfile) }
    }

    private var _defaultStyle: SuggestionStyle
    var defaultStyle: SuggestionStyle {
        get { _defaultStyle }
        set { _defaultStyle = newValue; defaults.set(newValue.rawValue, forKey: Key.defaultStyle) }
    }

    private var _historyEnabled: Bool
    /// Off during onboarding until the user explicitly enables it (PRD §15).
    var historyEnabled: Bool {
        get { _historyEnabled }
        set { _historyEnabled = newValue; defaults.set(newValue, forKey: Key.historyEnabled) }
    }

    private var _retention: RetentionPolicy
    var retention: RetentionPolicy {
        get { _retention }
        set { _retention = newValue; defaults.set(newValue.rawValue, forKey: Key.retention) }
    }

    private var _excludedApps: [ExcludedApp]
    var excludedApps: [ExcludedApp] {
        get { _excludedApps }
        set { _excludedApps = newValue; defaults.set(Self.encode(newValue), forKey: Key.excludedApps) }
    }

    private var _selectionPopupEnabled: Bool
    /// Off until the user asks for it. Turning it on means PromptBar starts
    /// reading selections in other apps, which is a different privacy posture
    /// from the hotkey — it must never be the default (PRD §22 P0 / §15).
    var selectionPopupEnabled: Bool {
        get { _selectionPopupEnabled }
        set { _selectionPopupEnabled = newValue; defaults.set(newValue, forKey: Key.selectionPopup) }
    }

    /// Mirrors the real `SMAppService` registration rather than a stored flag,
    /// so the toggle can never disagree with the system.
    private var _launchAtLogin: Bool
    var launchAtLogin: Bool {
        get { _launchAtLogin }
        set {
            LaunchAtLogin.setEnabled(newValue)
            _launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    func refreshLaunchAtLogin() { _launchAtLogin = LaunchAtLogin.isEnabled }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }

    // MARK: - Codable helpers

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
