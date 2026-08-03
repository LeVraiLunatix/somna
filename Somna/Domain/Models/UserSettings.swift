import Foundation

/// How long raw audio is kept.
///
/// The default is deliberately not "keep everything": a night is ~115 MB of raw
/// audio and ~10 MB once only its clips remain. Defaulting to unlimited would
/// quietly consume gigabytes of someone's phone for data they will never replay.
enum AudioRetentionPolicy: String, Codable, Sendable, CaseIterable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case keepAll
    /// Discard raw audio as soon as analysis finishes, keeping only clips.
    case clipsOnly

    var maximumAge: TimeInterval? {
        switch self {
        case .sevenDays: 7 * 24 * 3600
        case .thirtyDays: 30 * 24 * 3600
        case .ninetyDays: 90 * 24 * 3600
        case .keepAll: nil
        case .clipsOnly: 0
        }
    }

    /// Whether raw audio older than ``maximumAge`` should be purged.
    func shouldPurgeRawAudio(recordedAt: Date, now: Date) -> Bool {
        guard let maximumAge else { return false }
        return now.timeIntervalSince(recordedAt) >= maximumAge
    }
}

/// How eager the pipeline is to report a detection.
///
/// Only shifts the confidence thresholds; it never invents new event types.
enum AnalysisSensitivity: String, Codable, Sendable, CaseIterable {
    case conservative
    case balanced
    case sensitive

    /// Added to the rejection threshold. Positive values mean fewer, surer events.
    var thresholdOffset: Double {
        switch self {
        case .conservative: 0.10
        case .balanced: 0
        case .sensitive: -0.08
        }
    }
}

enum ThemePreference: String, Codable, Sendable, CaseIterable {
    case system
    case dark
    case light
}

/// User-controlled preferences.
///
/// Stored in `UserDefaults` rather than SwiftData: they are small, read on
/// nearly every screen, and must remain readable even if the persistent store
/// fails to open — the Settings screen has to work well enough to let someone
/// delete their data when something has gone wrong.
struct UserSettings: Equatable, Sendable, Codable {

    var theme: ThemePreference
    /// Which accent the app uses, and which icon it wears.
    var palette: ThemePalette
    var retentionPolicy: AudioRetentionPolicy
    var analysisSensitivity: AnalysisSensitivity

    /// Store only the audio around detections, discarding the rest immediately.
    var keepOnlyDetectedClips: Bool
    var useHighQualityAudio: Bool

    var eveningReminderEnabled: Bool
    /// Minutes from midnight, so the value is timezone-independent.
    var eveningReminderMinutes: Int
    /// Sent when an analysis finishes, not on a timer — see `NotificationService`.
    var morningSummaryEnabled: Bool
    var weeklyReportEnabled: Bool
    /// Minutes from midnight, like the evening reminder.
    var weeklyReportMinutes: Int

    /// Rings through Focus and the ring switch, via AlarmKit, and ends the
    /// night when it does.
    var wakeAlarmEnabled: Bool
    var wakeAlarmMinutes: Int

    /// Both default to `false` and stay `false` in v0.1: nothing in this version
    /// sends anything anywhere. They exist so the choice is recorded as opt-in
    /// from the start rather than being retrofitted later.
    var cloudProcessingConsent: Bool
    var analyticsConsent: Bool

    var reducedVisualEffects: Bool
    var hasCompletedOnboarding: Bool

    static let `default` = UserSettings(
        theme: .system,
        palette: .midnight,
        retentionPolicy: .sevenDays,
        analysisSensitivity: .balanced,
        keepOnlyDetectedClips: false,
        useHighQualityAudio: false,
        eveningReminderEnabled: false,
        eveningReminderMinutes: 22 * 60 + 30,
        morningSummaryEnabled: false,
        weeklyReportEnabled: false,
        weeklyReportMinutes: 9 * 60,
        wakeAlarmEnabled: false,
        wakeAlarmMinutes: 7 * 60,
        cloudProcessingConsent: false,
        analyticsConsent: false,
        reducedVisualEffects: false,
        hasCompletedOnboarding: false
    )
}

extension UserSettings {
    var audioBitRate: Int {
        useHighQualityAudio ? AudioConstants.highQualityBitRate : AudioConstants.defaultBitRate
    }

    /// Effective rejection threshold once the user's sensitivity is applied.
    var effectiveRejectionThreshold: Double {
        min(0.9, max(0.2, EventConfidence.rejectionThreshold + analysisSensitivity.thresholdOffset))
    }
}
