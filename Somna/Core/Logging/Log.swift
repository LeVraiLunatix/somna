import Foundation
import OSLog

/// Structured logging façade.
///
/// Somna records what people say and do while they sleep, so logging is a
/// privacy surface, not a debugging convenience. Two rules are enforced here
/// rather than left to reviewer discipline:
///
/// 1. **No audio-bearing path is ever logged in full.** Use ``redacted(_:)`` on
///    any file URL. A full path exposes the session identifier, and on a shared
///    or supervised device the Console is readable by others.
/// 2. **Identifiers are truncated.** ``short(_:)`` keeps eight characters — enough
///    to correlate two log lines within a session, not enough to be a stable
///    cross-session identifier.
///
/// `os.Logger` already redacts interpolated values as `<private>` in release
/// builds unless marked `.public`; nothing in Somna should ever be marked public
/// except literal state names and numbers.
enum Log {

    private static func logger(_ category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    private static let subsystem: String =
        Bundle.main.bundleIdentifier ?? "com.somna.app"

    static var app: Logger { logger(.app) }
    static var audio: Logger { logger(.audio) }
    static var analysis: Logger { logger(.analysis) }
    static var persistence: Logger { logger(.persistence) }
    static var notifications: Logger { logger(.notifications) }
    static var storage: Logger { logger(.storage) }
    static var privacy: Logger { logger(.privacy) }
    static var ui: Logger { logger(.ui) }

    /// Shortens an identifier for correlation without making it a durable handle.
    ///
    ///     Log.audio.debug("Segment closed for \(Log.short(session.id))")
    ///     // -> "Segment closed for 3F2A9C71"
    static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    /// Reduces a file URL to its last path component with the stem removed.
    ///
    /// Enough to know *which kind* of file misbehaved, never enough to point at
    /// a specific night's recording.
    ///
    ///     Log.storage.error("Failed to close \(Log.redacted(url))")
    ///     // -> "Failed to close <segment>.m4a"
    static func redacted(_ url: URL) -> String {
        let ext = url.pathExtension
        return ext.isEmpty ? "<file>" : "<file>.\(ext)"
    }
}
