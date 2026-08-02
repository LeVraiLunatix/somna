import Foundation

/// Where a night is in its lifecycle.
///
/// `interrupted` is a first-class state rather than a variant of `failed`: iOS
/// can end a recording for reasons the user did not choose, and those nights
/// still hold usable segments. Treating them as failures would throw away real
/// data and, worse, teach users that Somna loses nights.
enum NightSessionStatus: String, Codable, Sendable, CaseIterable {
    /// Currently capturing audio.
    case recording
    /// Capture stopped unexpectedly. Segments written so far are intact.
    case interrupted
    /// Capture finished cleanly; analysis has not run yet.
    case awaitingAnalysis
    /// Analysis in progress.
    case analyzing
    /// Analysis finished; the report is available.
    case completed
    /// Analysis could not produce a report.
    case failed
}

/// One night of recording, from tapping start to the report being ready.
struct NightSession: Identifiable, Equatable, Sendable {

    let id: UUID
    var startDate: Date
    var endDate: Date?
    var status: NightSessionStatus

    /// Audio actually captured, which is *not* `endDate - startDate` when the
    /// session was interrupted. The distinction matters: presenting wall-clock
    /// time as recorded time would inflate every statistic derived from it.
    var recordedDuration: TimeInterval

    var estimatedSleepStart: Date?
    var estimatedWakeTime: Date?

    /// 0–100 internal calmness indicator. Optional because it does not exist
    /// until analysis has run, and because a night with unusable audio must not
    /// be given a score at all rather than a misleading zero.
    var calmnessScore: Int?

    /// The summary, as statements rather than prose.
    ///
    /// Storing rendered text would freeze the language a night was recorded in.
    /// Statements are turned into words at display time, so switching the phone
    /// to English re-reads every past night correctly.
    var summaryStatements: [SummaryStatement]

    var statistics: NightStatistics?
    var recordingQuality: RecordingQuality?

    /// Version of the analysis pipeline that produced this report, so a night
    /// analysed by an older build can be identified and optionally re-analysed.
    var analysisVersion: String

    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        status: NightSessionStatus = .recording,
        recordedDuration: TimeInterval = 0,
        estimatedSleepStart: Date? = nil,
        estimatedWakeTime: Date? = nil,
        calmnessScore: Int? = nil,
        summaryStatements: [SummaryStatement] = [],
        statistics: NightStatistics? = nil,
        recordingQuality: RecordingQuality? = nil,
        analysisVersion: String = AnalysisConstants.currentVersion,
        isFavorite: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.recordedDuration = recordedDuration
        self.estimatedSleepStart = estimatedSleepStart
        self.estimatedWakeTime = estimatedWakeTime
        self.calmnessScore = calmnessScore
        self.summaryStatements = summaryStatements
        self.statistics = statistics
        self.recordingQuality = recordingQuality
        self.analysisVersion = analysisVersion
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension NightSession {

    /// Elapsed time between start and stop, regardless of how much was captured.
    var wallClockDuration: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(startDate))
    }

    /// How much of the elapsed night was actually captured, `nil` while running.
    ///
    /// Surfaced in the report's recording-quality section: a session at 60 %
    /// coverage had real interruptions, and the user deserves to know before
    /// reading conclusions drawn from it.
    var captureCoverage: Double? {
        let wallClock = wallClockDuration
        guard wallClock > 0 else { return nil }
        return min(1, recordedDuration / wallClock)
    }

    /// Whether there is enough audio for analysis to say anything meaningful.
    var isAnalysable: Bool {
        recordedDuration >= AnalysisConstants.minimumAnalysableDuration
    }

    var isFinished: Bool {
        switch status {
        case .completed, .failed: true
        case .recording, .interrupted, .awaitingAnalysis, .analyzing: false
        }
    }
}
