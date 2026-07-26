import Foundation
import Observation

/// Local-only enhancement history (PRD §15). Stored as JSON inside the
/// application container — never synced, never uploaded. Recording happens
/// only when the user has explicitly enabled history, and never for prompts
/// that came from an excluded app.
@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL?

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            fileURL = base.appendingPathComponent("history.json")
        } else {
            fileURL = nil
        }
        load()
    }

    // MARK: - Mutations

    func record(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    /// Drops entries older than the retention window.
    func prune(using policy: RetentionPolicy) {
        guard let days = policy.days else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != before { save() }
    }

    /// The most recent entries, for the menu-bar "Recent" section.
    func recent(_ limit: Int) -> [HistoryEntry] {
        Array(entries.prefix(limit))
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            // Never let one unreadable file silently erase the user's history:
            // the next write would overwrite it. Keep it for recovery instead.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("PromptBar: history unreadable, preserved at \(backup.lastPathComponent)")
            entries = []
        }
    }

    private func save() {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PromptBar", isDirectory: true)
    }
}
