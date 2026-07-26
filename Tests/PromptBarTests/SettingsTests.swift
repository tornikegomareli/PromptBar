import Testing
import Foundation
@testable import PromptBar

@Suite("History store")
@MainActor
struct HistoryStoreTests {
    /// A store rooted in a unique temp directory so tests never touch real data.
    private func makeStore() -> HistoryStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("promptbar-tests-\(UUID().uuidString)")
        return HistoryStore(directory: dir)
    }

    private func entry(daysAgo: Int = 0) -> HistoryEntry {
        HistoryEntry(
            original: "rough",
            enhanced: "polished",
            profile: .auto,
            style: .balanced,
            date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            wasEdited: false,
            wasCopied: true
        )
    }

    @Test("Records newest-first and clears")
    func recordAndClear() {
        let store = makeStore()
        store.record(entry())
        store.record(entry())
        #expect(store.entries.count == 2)
        store.clearAll()
        #expect(store.entries.isEmpty)
    }

    @Test("Prune drops entries past the retention window")
    func prune() {
        let store = makeStore()
        store.record(entry(daysAgo: 0))
        store.record(entry(daysAgo: 45))
        store.prune(using: .month)   // 30 days
        #expect(store.entries.count == 1)
    }

    @Test("Never retention keeps everything")
    func pruneNever() {
        let store = makeStore()
        store.record(entry(daysAgo: 400))
        store.prune(using: .never)
        #expect(store.entries.count == 1)
    }

    @Test("Entries survive a reload from disk")
    func persistence() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("promptbar-tests-\(UUID().uuidString)")
        let first = HistoryStore(directory: dir)
        first.record(entry())
        let second = HistoryStore(directory: dir)
        #expect(second.entries.count == 1)
        #expect(second.entries.first?.enhanced == "polished")
    }
}

@Suite("App settings")
@MainActor
struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        let suite = UserDefaults(suiteName: "promptbar-tests-\(UUID().uuidString)")!
        return AppSettings(defaults: suite)
    }

    @Test("Defaults match the PRD")
    func defaults() {
        let s = makeSettings()
        #expect(s.defaultProfile == .auto)
        #expect(s.defaultStyle == .balanced)
        // History is off until the user explicitly enables it (PRD §15).
        #expect(s.historyEnabled == false)
        #expect(s.retention == .month)
    }

    @Test("Preferences round-trip through UserDefaults")
    func roundTrip() {
        let suite = UserDefaults(suiteName: "promptbar-rt-\(UUID().uuidString)")!
        let a = AppSettings(defaults: suite)
        a.defaultProfile = .codingAgent
        a.defaultStyle = .structured
        a.historyEnabled = true
        a.retention = .quarter
        a.excludedApps = [ExcludedApp(bundleID: "com.apple.Notes", name: "Notes")]

        let b = AppSettings(defaults: suite)
        #expect(b.defaultProfile == .codingAgent)
        #expect(b.defaultStyle == .structured)
        #expect(b.historyEnabled)
        #expect(b.retention == .quarter)
        #expect(b.excludedApps.map(\.name) == ["Notes"])
    }

    @Test("Excluded apps are matched by bundle ID")
    func exclusion() {
        let s = makeSettings()
        s.excludedApps = [ExcludedApp(bundleID: "com.agilebits.onepassword7", name: "1Password")]
        #expect(s.isExcluded(bundleID: "com.agilebits.onepassword7"))
        #expect(!s.isExcluded(bundleID: "com.apple.Safari"))
        #expect(!s.isExcluded(bundleID: nil))
    }
}
