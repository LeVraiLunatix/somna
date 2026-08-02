import Foundation

/// Tuning of the analysis pipeline.
///
/// Kept in one place so the behaviour of the app can be reasoned about without
/// reading the engine, and so a night can record which values produced it.
enum AnalysisConstants {

    /// Bumped whenever the pipeline changes in a way that would produce
    /// different events from the same audio. Stored on each `NightSession` so
    /// old reports remain identifiable and can be re-analysed deliberately.
    static let currentVersion = "1.0.0"

    /// Below this, a session is not analysed: a two-minute recording cannot
    /// support any statement about a night, and pretending otherwise is exactly
    /// the kind of false precision this app avoids.
    static let minimumAnalysableDuration: TimeInterval = 5 * 60

    /// Detections of the same type closer than this are merged into one grouped
    /// timeline entry. Ninety seconds keeps a snoring bout as a single row while
    /// leaving genuinely separate coughs apart.
    static let groupingWindow: TimeInterval = 90

    /// Audio kept either side of a detection when extracting its clip. Enough
    /// context to recognise the sound, short enough to stay cheap to store.
    static let clipPadding: TimeInterval = 3

    /// A stretch of quiet must last at least this long before it counts as a
    /// calm period, which prevents a gap between two snores being called calm.
    static let minimumCalmPeriod: TimeInterval = 10 * 60

    /// Sleep onset and wake time are only shown when the surrounding evidence is
    /// at least this clear. Below it, the estimate is omitted entirely rather
    /// than displayed with a caveat nobody reads.
    static let sleepWindowMinimumConfidence: Double = 0.5
}
