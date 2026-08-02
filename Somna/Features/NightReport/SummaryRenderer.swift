import Foundation

/// Turns summary statements into sentences.
///
/// Lives outside `Domain` on purpose: the domain decides *what is true* about a
/// night, this decides *how to say it*. Keeping them apart is what lets the same
/// stored night read in French today and in English tomorrow, and it keeps
/// `Bundle` out of the layer that has to stay testable without one.
enum SummaryRenderer {

    static func sentences(
        for statements: [SummaryStatement],
        locale: Locale = .current
    ) -> [String] {
        statements.map { sentence(for: $0, locale: locale) }
    }

    /// The whole summary as one paragraph.
    static func paragraph(
        for statements: [SummaryStatement],
        locale: Locale = .current
    ) -> String {
        sentences(for: statements, locale: locale).joined(separator: " ")
    }

    static func sentence(for statement: SummaryStatement, locale: Locale = .current) -> String {
        switch statement {

        case .overallCalm:
            String(localized: "summary.overallCalm",
                   defaultValue: "Your night stayed quiet overall.")

        case .overallActive(let count):
            String(localized: "summary.overallActive",
                   defaultValue: "It was a busy night, with \(count) events picked up.")

        case .snoringConcentrated(let start, let end, let total):
            String(localized: "summary.snoringConcentrated",
                   defaultValue: "Snoring was detected mostly between \(time(start, locale)) and \(time(end, locale)), for about \(duration(total, locale)) in total.")

        case .snoringScattered(let total):
            String(localized: "summary.snoringScattered",
                   defaultValue: "Snoring was detected on and off through the night, for about \(duration(total, locale)) in total.")

        case .coughs(let count):
            String(localized: "summary.coughs",
                   defaultValue: "\(count) coughs were detected.")

        case .speech(let total):
            String(localized: "summary.speech",
                   defaultValue: "Somna heard about \(duration(total, locale)) of speech.")

        case .loudEvent(let date):
            String(localized: "summary.loudEvent",
                   defaultValue: "A loud sound was recorded around \(time(date, locale)).")

        case .calmestStretch(let start, let end):
            String(localized: "summary.calmestStretch",
                   defaultValue: "The quietest stretch ran from \(time(start, locale)) to \(time(end, locale)).")

        case .interrupted(let count):
            // Never softened: without this, every count above it is an undercount.
            String(localized: "summary.interrupted",
                   defaultValue: "Recording was interrupted \(count) times, so parts of the night were not captured.")

        case .qualityUnusable:
            String(localized: "summary.qualityUnusable",
                   defaultValue: "The recording was too degraded to draw anything from. This says nothing about your night — only about the audio.")

        case .tooShort:
            String(localized: "summary.tooShort",
                   defaultValue: "This session was too short for Somna to detect anything.")

        case .nothingDetected:
            String(localized: "summary.nothingDetected",
                   defaultValue: "Somna did not detect anything at all. Either the night was remarkably quiet, or the microphone was not picking much up.")
        }
    }

    // MARK: - Formatting

    /// Time of day, in the user's 12- or 24-hour preference.
    private static func time(_ date: Date, _ locale: Locale) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// Durations are deliberately rounded to whole minutes here. "42 minutes" is
    /// a claim the analysis can support; "42 minutes and 17 seconds" implies a
    /// precision the detection does not have.
    private static func duration(_ interval: TimeInterval, _ locale: Locale) -> String {
        interval.formattedDuration(locale: locale)
    }
}
