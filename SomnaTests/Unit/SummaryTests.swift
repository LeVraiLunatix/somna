import Foundation
import Testing

@testable import Somna

/// The summary is the only place in Somna that produces prose about someone's
/// night. It is therefore the only place that could invent one.
///
/// These tests enforce that it cannot: every statement it emits must trace back
/// to a value in ``SummaryFacts``, and the two cases where saying anything at all
/// would be dishonest must end the summary rather than preface it.
struct SummaryGeneratorTests {

    private let generator = TemplateSummaryGenerator()
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func facts(
        recorded: TimeInterval = 8 * 3600,
        analysable: Bool = true,
        quality: RecordingQualityRating = .good,
        coverage: Double = 1,
        gaps: Int = 0,
        statistics: NightStatistics = .empty,
        snoringWindow: DateInterval? = nil,
        loudest: Date? = nil
    ) -> SummaryFacts {
        SummaryFacts(
            recordedDuration: recorded,
            isAnalysable: analysable,
            quality: quality,
            coverage: coverage,
            gapCount: gaps,
            statistics: statistics,
            snoringWindow: snoringWindow,
            loudestEventDate: loudest
        )
    }

    private func stats(
        recorded: TimeInterval = 8 * 3600,
        snoring: TimeInterval = 0,
        coughs: Int = 0,
        talking: TimeInterval = 0,
        loud: Int = 0,
        total: Int = 0,
        counts: [NightEventType: Int] = [:],
        calmest: DateInterval? = nil
    ) -> NightStatistics {
        NightStatistics(
            recordedDuration: recorded,
            quietDuration: max(0, recorded - snoring - talking),
            snoringDuration: snoring,
            coughCount: coughs,
            talkingDuration: talking,
            loudEventCount: loud,
            totalEventCount: total,
            eventCountsByType: counts,
            calmestPeriod: calmest,
            busiestHour: nil
        )
    }

    // MARK: - The invariant

    /// The central guarantee: nothing in the output exists that is not in the
    /// input. Checked by reading the numbers back out of the statements and
    /// comparing them to the facts they came from.
    @Test("Every number in the summary comes from the facts")
    func summaryOnlyRestatesFacts() {
        let input = facts(
            gaps: 2,
            statistics: stats(snoring: 1800, coughs: 4, talking: 120, total: 30,
                              counts: [.snoring: 20, .coughing: 4]),
            loudest: origin.addingTimeInterval(4 * 3600)
        )

        for statement in generator.summarise(input) {
            switch statement {
            case .coughs(let count):
                #expect(count == input.statistics.coughCount)
            case .speech(let total):
                #expect(total == input.statistics.talkingDuration)
            case .snoringScattered(let total), .snoringConcentrated(_, _, let total):
                #expect(total == input.statistics.snoringDuration)
            case .interrupted(let count):
                #expect(count == input.gapCount)
            case .loudEvent(let date):
                #expect(date == input.loudestEventDate)
            case .overallActive(let count):
                #expect(count == input.statistics.totalEventCount)
            case .calmestStretch(let start, let end):
                #expect(input.statistics.calmestPeriod == DateInterval(start: start, end: end))
            case .overallCalm, .qualityUnusable, .tooShort, .nothingDetected:
                break
            }
        }
    }

    @Test("Nothing detected is never described as coughing or snoring")
    func emptyNightSaysNothingHappened() {
        let statements = generator.summarise(facts(statistics: stats()))

        #expect(statements.contains(.nothingDetected))
        #expect(!statements.contains { if case .coughs = $0 { true } else { false } })
        #expect(!statements.contains { if case .snoringScattered = $0 { true } else { false } })
    }

    // MARK: - Honest refusals

    /// Saying anything else about an unusable recording would be dishonest, so
    /// this ends the summary rather than prefacing it.
    @Test("An unusable recording produces only that statement")
    func unusableRecordingSaysOnlyThat() {
        let statements = generator.summarise(
            facts(quality: .unusable, statistics: stats(snoring: 3600, coughs: 12, total: 90))
        )
        #expect(statements == [.qualityUnusable])
    }

    @Test("A session too short produces only that statement")
    func shortSessionSaysOnlyThat() {
        let statements = generator.summarise(
            facts(recorded: 120, analysable: false, statistics: stats(coughs: 3, total: 3))
        )
        #expect(statements == [.tooShort])
    }

    /// Without this, every count above it is silently an undercount.
    @Test("Interruptions are always reported when they happened")
    func interruptionsAreAlwaysMentioned() {
        let statements = generator.summarise(
            facts(gaps: 3, statistics: stats(total: 5))
        )
        #expect(statements.contains(.interrupted(gapCount: 3)))
    }

    // MARK: - Shape of the night

    @Test("Concentrated snoring is described with its window")
    func concentratedSnoringNamesTheWindow() {
        let window = DateInterval(
            start: origin.addingTimeInterval(3600),
            end: origin.addingTimeInterval(7200)
        )
        let statements = generator.summarise(
            facts(statistics: stats(snoring: 2400, total: 20, counts: [.snoring: 20]),
                  snoringWindow: window)
        )

        #expect(statements.contains(.snoringConcentrated(
            start: window.start, end: window.end, total: 2400
        )))
    }

    @Test("Scattered snoring is not given a misleading window")
    func scatteredSnoringHasNoWindow() {
        let statements = generator.summarise(
            facts(statistics: stats(snoring: 2400, total: 20, counts: [.snoring: 20]))
        )
        #expect(statements.contains(.snoringScattered(total: 2400)))
    }

    @Test("A trace of snoring is not reported at all")
    func negligibleSnoringIsOmitted() {
        let statements = generator.summarise(
            facts(statistics: stats(snoring: 30, total: 2, counts: [.snoring: 2]))
        )
        #expect(!statements.contains { if case .snoringScattered = $0 { true } else { false } })
    }

    @Test("A busy night is described as busy")
    func busyNightIsCalledBusy() {
        let statements = generator.summarise(
            facts(statistics: stats(recorded: 3600, total: 40))
        )
        #expect(statements.contains(.overallActive(eventCount: 40)))
    }

    @Test("A quiet night is described as quiet")
    func quietNightIsCalledQuiet() {
        let statements = generator.summarise(
            facts(statistics: stats(coughs: 3, total: 3))
        )
        #expect(statements.contains(SummaryStatement.overallCalm))
    }

    /// On an already silent night, naming the quietest stretch says nothing.
    @Test("The calmest stretch is only named when the night had activity")
    func calmestStretchNeedsContext() {
        let calm = DateInterval(start: origin, end: origin.addingTimeInterval(3600))

        let quiet = generator.summarise(facts(statistics: stats(total: 2, calmest: calm)))
        #expect(!quiet.contains { if case .calmestStretch = $0 { true } else { false } })

        let busy = generator.summarise(facts(statistics: stats(total: 20, calmest: calm)))
        #expect(busy.contains(.calmestStretch(start: calm.start, end: calm.end)))
    }

    /// A summary that reads differently for the same night would make people
    /// doubt the data, and the data is the whole product.
    @Test("The same night always summarises identically")
    func summaryIsDeterministic() {
        let input = facts(statistics: stats(snoring: 1800, coughs: 4, total: 30))
        #expect(generator.summarise(input) == generator.summarise(input))
    }

    @Test("A summary always says something")
    func summaryIsNeverEmpty() {
        #expect(!generator.summarise(facts(statistics: stats())).isEmpty)
        #expect(!generator.summarise(facts(analysable: false)).isEmpty)
        #expect(!generator.summarise(facts(quality: .unusable)).isEmpty)
    }
}

struct SummaryFactsTests {

    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID()

    private func snore(at offset: TimeInterval, duration: TimeInterval = 60) -> NightEvent {
        NightEvent(
            sessionID: sessionID,
            type: .snoring,
            confidence: .high,
            startDate: origin.addingTimeInterval(offset),
            endDate: origin.addingTimeInterval(offset + duration),
            createdAt: origin
        )
    }

    /// "Between 23:10 and 06:40" is technically true and completely useless.
    @Test("Snoring spread across the whole night gets no window")
    func spreadSnoringHasNoWindow() {
        let events = [snore(at: 0), snore(at: 7 * 3600)]
        let facts = SummaryFacts.make(
            session: NightSession(startDate: origin, endDate: origin.addingTimeInterval(8 * 3600),
                                  status: .completed, recordedDuration: 8 * 3600,
                                  createdAt: origin, updatedAt: origin),
            events: events,
            statistics: .empty,
            gapCount: 0
        )
        #expect(facts.snoringWindow == nil)
    }

    @Test("Snoring clustered in one stretch gets a window")
    func clusteredSnoringHasWindow() throws {
        let events = (0..<10).map { snore(at: Double($0) * 90) }
        let facts = SummaryFacts.make(
            session: NightSession(startDate: origin, endDate: origin.addingTimeInterval(8 * 3600),
                                  status: .completed, recordedDuration: 8 * 3600,
                                  createdAt: origin, updatedAt: origin),
            events: events,
            statistics: .empty,
            gapCount: 0
        )
        let window = try #require(facts.snoringWindow)
        #expect(window.start == origin)
    }

    @Test("A single snore is not a window")
    func singleSnoreHasNoWindow() {
        let facts = SummaryFacts.make(
            session: NightSession(startDate: origin, endDate: origin.addingTimeInterval(8 * 3600),
                                  status: .completed, recordedDuration: 8 * 3600,
                                  createdAt: origin, updatedAt: origin),
            events: [snore(at: 3600)],
            statistics: .empty,
            gapCount: 0
        )
        #expect(facts.snoringWindow == nil)
    }
}

struct SummaryRendererTests {

    @Test("Every statement renders to a non-empty sentence")
    func everyStatementRenders() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let statements: [SummaryStatement] = [
            .overallCalm,
            .overallActive(eventCount: 30),
            .snoringConcentrated(start: date, end: date.addingTimeInterval(3600), total: 1800),
            .snoringScattered(total: 1800),
            .coughs(count: 4),
            .speech(total: 120),
            .loudEvent(at: date),
            .calmestStretch(start: date, end: date.addingTimeInterval(3600)),
            .interrupted(gapCount: 2),
            .qualityUnusable,
            .tooShort,
            .nothingDetected,
        ]

        for statement in statements {
            let sentence = SummaryRenderer.sentence(for: statement, locale: Locale(identifier: "en_GB"))
            #expect(!sentence.isEmpty, "\(statement) rendered to nothing")
        }
    }

    /// The unusable-recording sentence has to separate the recording from the
    /// night, or someone reads a bad microphone as a bad night.
    @Test("An unusable recording is not described as a bad night")
    func unusableSentenceBlamesTheAudio() {
        let sentence = SummaryRenderer
            .sentence(for: .qualityUnusable, locale: Locale(identifier: "en_GB"))
            .lowercased()
        #expect(sentence.contains("audio") || sentence.contains("recording"))
    }

    @Test("Statements join into one readable paragraph")
    func paragraphJoinsSentences() {
        let paragraph = SummaryRenderer.paragraph(
            for: [.overallCalm, .coughs(count: 3)],
            locale: Locale(identifier: "en_GB")
        )
        #expect(paragraph.contains("3"))
        #expect(paragraph.count > 20)
    }

    @Test("An empty summary renders to nothing rather than a stray space")
    func emptyParagraph() {
        #expect(SummaryRenderer.paragraph(for: []).isEmpty)
    }
}
