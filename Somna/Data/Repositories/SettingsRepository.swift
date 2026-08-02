import Foundation
import Synchronization
import OSLog

/// Reads and writes ``UserSettings``.
protocol SettingsStoring: Sendable {
    func load() -> UserSettings
    func save(_ settings: UserSettings)
}

/// `UserDefaults`-backed settings.
///
/// Stored as a single JSON blob under one key rather than as a dozen scalars.
/// Settings are read and written as a unit, and one key means one decode path
/// and one place where a schema change has to be handled — instead of a dozen
/// keys that can drift out of sync with each other.
///
/// A decode failure falls back to defaults rather than throwing: settings are
/// preferences, never data. Losing them is an annoyance; blocking launch over
/// them would be a bug.
struct SettingsRepository: SettingsStoring {

    /// `UserDefaults` is documented as thread-safe but is not annotated
    /// `Sendable`. `nonisolated(unsafe)` on this one property is the narrow
    /// escape hatch — narrower than marking the whole type `@unchecked Sendable`,
    /// which would also silence future genuinely unsafe additions.
    nonisolated(unsafe) private let defaults: UserDefaults

    private let key = "somna.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        do {
            return try JSONDecoder().decode(UserSettings.self, from: data)
        } catch {
            Log.persistence.error("Settings decode failed, falling back to defaults")
            return .default
        }
    }

    func save(_ settings: UserSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            Log.persistence.error("Settings encode failed; change not persisted")
        }
    }
}

/// In-memory settings for previews and tests.
///
/// Uses `Mutex` rather than a hand-rolled lock behind `@unchecked Sendable`:
/// the compiler verifies the isolation instead of a comment promising it.
///
/// A `final class` rather than a struct because `Mutex` is non-copyable and
/// therefore cannot be stored in a copyable value type.
final class InMemorySettingsRepository: SettingsStoring {

    private let storage: Mutex<UserSettings>

    init(_ settings: UserSettings = .default) {
        storage = Mutex(settings)
    }

    func load() -> UserSettings {
        storage.withLock { $0 }
    }

    func save(_ settings: UserSettings) {
        storage.withLock { $0 = settings }
    }
}
