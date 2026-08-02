import Foundation
import Testing

@testable import Somna

private let origin = Date(timeIntervalSince1970: 1_800_000_000)
private let sessionID = UUID()

private func event(
    _ type: NightEventType,
    at offset: TimeInterval,
    duration: TimeInterval = 10,
    confidence: EventConfidence = .high,
    peak: Double = 0.4,
    count: Int = 1,
    clip: String? = nil
) -> NightEvent {
    NightEvent(
        sessionID: sessionID,
        type: type,
        confidence: confidence,
        startDate: origin.addingTimeInterval(offset),
        endDate: origin.addingTimeInterval(offset + duration),
        occurrenceCount: count,
        peakLevel: peak,
        clipFileName: clip,
        createdAt: origin
    )
}

private func session(
    recorded: TimeInterval = 8 * 3600,
    wallClock: TimeInterval = 8 * 3600,
    quality: RecordingQuality? = nil
) -> NightSession {
    NightSession(
        startDate: origin,
        endDate: origin.addingTimeInterval(wallClock),
        status: .completed,
        recordedDuration: recorded,
        recordingQuality: quality,
        createdAt: origin,
        updatedAt: origin
    )
}

struct EventGrouperTests {

    /// Twelve snores in half an hour must be one row. Without grouping, the
    /// events that actually matter — a cough, a door — are buried.
    @Test("Consecutive events of the same kind become one entry")
    func consecutiveEventsMerge() {
        let events = (0..<12).map { event(.snoring, at: Double($0) * 60) }
        let grouped = EventGrouper.group(events)

        #expect(grouped.count == 1)
        #expect(grouped.first?.occurrenceCount == 12)
        #expect(grouped.first?.isGrouped == true)
    }

    @Test("Events further apart than the window stay separate")
    func distantEventsStaySeparate() {
        let grouped = EventGrouper.group([
            event(.coughing, at: 0),
            event(.coughing, at: AnalysisConstants.groupingWindow + 60),
        ])
        #expect(grouped.count == 2)
    }

    @Test("Different kinds never merge, however close")
    func differentKindsNeverMerge() {
        let grouped = EventGrouper.group([
            event(.snoring, at: 0),
            event(.coughing, at: 5),
        ])
        #expect(grouped.count == 2)
    }

    /// Merging two interruptions would hide that there were two, which is the
    /// opposite of what a gap is for.
    @Test("Session gaps are never merged")
    func gapsNeverMerge() {
        let grouped = EventGrouper.group([
            event(.sessionGap, at: 0),
            event(.sessionGap, at: 10),
        ])
        #expect(grouped.count == 2)
    }

    /// If one snore in a bout was unmistakable, the bout was snoring.
    @Test("A group is as confident as its strongest member")
    func groupTakesHighestConfidence() {
        let grouped = EventGrouper.group([
            event(.snoring, at: 0, confidence: .low),
            event(.snoring, at: 30, confidence: .high),
        ])
        #expect(grouped.first?.confidence == .high)
    }

    /// The clip kept is the one worth listening to when checking the guess.
    @Test("A group keeps the clip of its loudest member")
    func groupKeepsLoudestClip() {
        let grouped = EventGrouper.group([
            event(.snoring, at: 0, peak: 0.3, clip: "quiet.m4a"),
            event(.snoring, at: 30, peak: 0.9, clip: "loud.m4a"),
        ])
        #expect(grouped.first?.clipFileName == "loud.m4a")
        #expect(grouped.first?.peakLevel == 0.9)
    }

    @Test("A favourite anywhere in the group survives")
    func favouriteSurvives() {
        var favourite = event(.snoring, at: 30)
        favourite.isFavorite = true

        let grouped = EventGrouper.group([event(.snoring, at: 0), favourite])
        #expect(grouped.first?.isFavorite == true)
    }

    @Test("A user correction regroups the event with what they said it was")
    func correctionDrivesGrouping() {
        var corrected = event(.snoring, at: 30)
        corrected.userCorrectedType = .coughing

        let grouped = EventGrouper.group([event(.coughing, at: 0), corrected])
        #expect(grouped.count == 1)
        #expect(grouped.first?.effectiveType == .coughing)
    }

    @Test("Grouping is stable and order-independent")
    func groupingIsStable() {
        let events = [event(.snoring, at: 120), event(.snoring, at: 0), event(.snoring, at: 60)]
        let grouped = EventGrouper.group(events)
        #expect(grouped.count == 1)
        #expect(grouped.first?.startDate == origin)
    }

    @Test("An empty night groups to nothing")
    func emptyInput() {
        #expect(EventGrouper.group([]).isEmpty)
    }
}

struct CalmnessScoreTests {

    @Test("A silent night scores full marks")
    func silentNightScoresHigh() {
        let score = CalmnessScoreCalculator.score(
            statistics: NightStatistics(
                recordedDuration: 8 * 3600, quietDuration: 8 * 3600,
                snoringDuration: 0, coughCount: 0, talkingDuration: 0,
                loudEventCount: 0, totalEventCount: 0, eventCountsByType: [:],
                calmestPeriod: nil, busiestHour: nil
            ),
            quality: RecordingQuality(rating: .excellent),
            isAnalysable: true
        )
        #expect(score == 100)
    }

    @Test("More snoring always scores lower")
    func snoringLowersScore() {
        func score(snoringHours: Double) -> Int? {
            CalmnessScoreCalculator.score(
                statistics: NightStatistics(
                    recordedDuration: 8 * 3600, quietDuration: 0,
                    snoringDuration: snoringHours * 3600, coughCount: 0, talkingDuration: 0,
                    loudEventCount: 0, totalEventCount: 10,
                    eventCountsByType: [.snoring: 10], calmestPeriod: nil, busiestHour: nil
                ),
                quality: RecordingQuality(rating: .good),
                isAnalysable: true
            )
        }

        let light = try? #require(score(snoringHours: 0.5))
        let heavy = try? #require(score(snoringHours: 4))
        #expect((light ?? 0) > (heavy ?? 0))
    }

    /// A number on an unusable night would give it a precision it does not have,
    /// and a low score would read as "a bad night" rather than "a bad recording".
    @Test("An unusable recording gets no score at all")
    func unusableRecordingHasNoScore() {
        let score = CalmnessScoreCalculator.score(
            statistics: .empty,
            quality: RecordingQuality(rating: .unusable),
            isAnalysable: true
        )
        #expect(score == nil)
    }

    @Test("A night too short to analyse gets no score")
    func shortNightHasNoScore() {
        #expect(CalmnessScoreCalculator.score(
            statistics: .empty, quality: nil, isAnalysable: false
        ) == nil)
    }

    /// A night with heavy snoring but nothing else should not score zero, and
    /// one loud bang should not erase an otherwise peaceful night.
    @Test("No single factor can drive the score to zero")
    func factorsAreCapped() {
        let allSnoring = CalmnessScoreCalculator.score(
            statistics: NightStatistics(
                recordedDuration: 8 * 3600, quietDuration: 0,
                snoringDuration: 8 * 3600, coughCount: 0, talkingDuration: 0,
                loudEventCount: 0, totalEventCount: 100,
                eventCountsByType: [.snoring: 100], calmestPeriod: nil, busiestHour: nil
            ),
            quality: RecordingQuality(rating: .good),
            isAnalysable: true
        )
        #expect((allSnoring ?? 0) > 40)
    }

    @Test("The score always lands in 0...100")
    func scoreIsBounded() {
        let worst = CalmnessScoreCalculator.score(
            statistics: NightStatistics(
                recordedDuration: 3600, quietDuration: 0,
                snoringDuration: 3600, coughCount: 200, talkingDuration: 3600,
                loudEventCount: 500, totalEventCount: 2000,
                eventCountsByType: [:], calmestPeriod: nil, busiestHour: nil
            ),
            quality: RecordingQuality(rating: .poor, coverage: 0.3),
            isAnalysable: true
        )
        let value = worst ?? 0
        #expect(value >= 0 && value <= 100)
    }

    @Test("The same night always scores the same")
    func scoringIsDeterministic() {
        let stats = NightStatistics(
            recordedDuration: 7 * 3600, quietDuration: 5 * 3600,
            snoringDuration: 1800, coughCount: 4, talkingDuration: 60,
            loudEventCount: 2, totalEventCount: 40,
            eventCountsByType: [.snoring: 20], calmestPeriod: nil, busiestHour: nil
        )
        let quality = RecordingQuality(rating: .good, coverage: 0.95)

        let first = CalmnessScoreCalculator.score(statistics: stats, quality: quality, isAnalysable: true)
        let second = CalmnessScoreCalculator.score(statistics: stats, quality: quality, isAnalysable: true)
        #expect(first == second)
    }

    @Test("Bands follow the score")
    func bands() {
        #expect(CalmnessScoreCalculator.Band(score: 92) == .veryCalm)
        #expect(CalmnessScoreCalculator.Band(score: 70) == .calm)
        #expect(CalmnessScoreCalculator.Band(score: 50) == .someActivity)
        #expect(CalmnessScoreCalculator.Band(score: 12) == .restless)
    }
}

struct StatisticsTests {

    private let calendar = Calendar(identifier: .gregorian)

    /// Counting gaps as events would make an interrupted night look busier than
    /// it was.
    @Test("Session gaps are excluded from the counts")
    func gapsAreNotEvents() {
        let stats = StatisticsCalculator.statistics(
            events: [event(.snoring, at: 0), event(.sessionGap, at: 100, duration: 600)],
            session: session(),
            calendar: calendar
        )
        #expect(stats.totalEventCount == 1)
    }

    @Test("Grouped events count by their occurrences")
    func groupedEventsCountFully() {
        let stats = StatisticsCalculator.statistics(
            events: [event(.coughing, at: 0, count: 7)],
            session: session(),
            calendar: calendar
        )
        #expect(stats.coughCount == 7)
        #expect(stats.totalEventCount == 7)
    }

    @Test("Quiet time is what is left over, never negative")
    func quietTimeIsRemainder() {
        let stats = StatisticsCalculator.statistics(
            events: [event(.snoring, at: 0, duration: 3600)],
            session: session(recorded: 7200),
            calendar: calendar
        )
        #expect(stats.quietDuration == 3600)
        #expect(stats.quietFraction == 0.5)
    }

    /// A two-minute gap between snores is not a calm period, and calling it one
    /// would be exactly the false precision this app avoids.
    @Test("A short gap is not reported as a calm period")
    func shortGapIsNotCalm() {
        let events = [event(.snoring, at: 0), event(.snoring, at: 120)]
        let period = StatisticsCalculator.calmestPeriod(events: events, session: session(recorded: 300, wallClock: 300))
        #expect(period == nil)
    }

    @Test("A long quiet stretch is reported")
    func longQuietStretchIsFound() throws {
        let events = [event(.snoring, at: 0), event(.snoring, at: 3600)]
        let period = try #require(
            StatisticsCalculator.calmestPeriod(events: events, session: session())
        )
        #expect(period.duration >= AnalysisConstants.minimumCalmPeriod)
    }

    /// A statistic that moves between runs is not a statistic.
    @Test("Ties in the busiest hour resolve deterministically")
    func busiestHourIsDeterministic() {
        let events = [event(.snoring, at: 0), event(.coughing, at: 3600)]
        let first = StatisticsCalculator.busiestHour(events: events, calendar: calendar)
        let second = StatisticsCalculator.busiestHour(events: events.reversed(), calendar: calendar)
        #expect(first == second)
    }
}

struct SleepWindowEstimatorTests {

    /// Somna sees a long quiet stretch; it does not see sleep. When the evidence
    /// is weak the estimate is omitted rather than shown with a caveat nobody reads.
    @Test("A night with no sustained quiet yields no estimate")
    func noQuietNoEstimate() {
        let events = (0..<60).map { event(.snoring, at: Double($0) * 60) }
        let estimate = SleepWindowEstimator.estimate(events: events, session: session(recorded: 3600, wallClock: 3600))

        #expect(estimate.sleepStart == nil)
        #expect(estimate.wakeTime == nil)
    }

    @Test("A quiet middle yields both estimates")
    func quietMiddleYieldsEstimates() throws {
        let events = [
            event(.movementNoise, at: 300),
            event(.movementNoise, at: 7 * 3600),
        ]
        let estimate = SleepWindowEstimator.estimate(events: events, session: session())

        let sleepStart = try #require(estimate.sleepStart)
        let wake = try #require(estimate.wakeTime)
        #expect(sleepStart > origin)
        #expect(wake > sleepStart)
    }

    @Test("A session too short to analyse yields no estimate")
    func shortSessionYieldsNothing() {
        let estimate = SleepWindowEstimator.estimate(
            events: [], session: session(recorded: 60, wallClock: 60)
        )
        #expect(estimate.sleepStart == nil)
    }

    /// Otherwise the "estimate" is just the session bounds wearing a label.
    @Test("An estimate matching the session bounds is not offered")
    func boundsAreNotAnEstimate() {
        let estimate = SleepWindowEstimator.estimate(events: [], session: session())
        #expect(estimate.sleepStart == nil)
        #expect(estimate.wakeTime == nil)
    }
}

struct RecordingQualityAssessorTests {

    /// A microphone under a pillow and a genuinely silent room look identical in
    /// the average. What separates them is that a real room has peaks.
    @Test("A recording with no peak at all is unusable, not quiet")
    func deafRecordingIsUnusable() {
        let quality = RecordingQualityAssessor.assess(
            session: session(), events: [],
            averageNoiseFloor: 0.0001, peakLevel: 0.0005, gapCount: 0
        )
        #expect(quality.rating == .unusable)
        #expect(quality.issues.contains(.microphoneObstructed))
        #expect(quality.suppressesConclusions)
    }

    @Test("A clean full-coverage night rates excellent")
    func cleanNightIsExcellent() {
        let quality = RecordingQualityAssessor.assess(
            session: session(), events: [],
            averageNoiseFloor: 0.05, peakLevel: 0.6, gapCount: 0
        )
        #expect(quality.rating == .excellent)
        #expect(quality.issues.isEmpty)
    }

    @Test("A noisy room is flagged and downgraded")
    func noisyRoomIsPoor() {
        let quality = RecordingQualityAssessor.assess(
            session: session(), events: [],
            averageNoiseFloor: 0.35, peakLevel: 0.6, gapCount: 0
        )
        #expect(quality.issues.contains(.highConstantNoise))
        #expect(quality.rating == .poor)
    }

    @Test("Interruptions are recorded as an issue")
    func interruptionsAreFlagged() {
        let quality = RecordingQualityAssessor.assess(
            session: session(recorded: 4 * 3600, wallClock: 8 * 3600),
            events: [], averageNoiseFloor: 0.05, peakLevel: 0.6, gapCount: 3
        )
        #expect(quality.issues.contains(.sessionInterrupted))
    }

    @Test("Barely any coverage makes a night unusable")
    func tinyCoverageIsUnusable() {
        let quality = RecordingQualityAssessor.assess(
            session: session(recorded: 3600, wallClock: 8 * 3600),
            events: [], averageNoiseFloor: 0.05, peakLevel: 0.6, gapCount: 5
        )
        #expect(quality.rating == .unusable)
    }

    @Test("Every issue carries advice")
    func issuesCarryAdvice() {
        for issue in RecordingIssue.allCases {
            #expect(!issue.advice.isEmpty)
        }
    }
}
