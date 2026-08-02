import Foundation

/// Produces a night's summary.
///
/// A protocol so a future on-device language model can replace the templates
/// without any screen changing. That replacement is v0.2 work and is gated on
/// one condition: whatever generates the text must still only receive
/// ``SummaryFacts``, so it cannot invent an event either.
protocol SummaryGenerating: Sendable {
    func summarise(_ facts: SummaryFacts) -> [SummaryStatement]
}

/// The v0.1 generator: rules over facts, no free text anywhere.
///
/// The output varies with the shape of the night — duration, density,
/// distribution, quality — rather than by picking randomly from phrasings. A
/// summary that reads differently for the same night would make people doubt the
/// data, and the data is the whole product.
struct TemplateSummaryGenerator: SummaryGenerating {

    /// Above this many events per hour, a night is described as active rather
    /// than calm.
    static let activeEventsPerHour = 12.0

    /// Snoring below this share of the night is mentioned but not emphasised.
    static let significantSnoringFraction = 0.05

    func summarise(_ facts: SummaryFacts) -> [SummaryStatement] {

        // Two cases where saying anything else would be dishonest, so they end
        // the summary rather than prefacing it.
        guard facts.isAnalysable else { return [.tooShort] }
        guard facts.quality != .unusable else { return [.qualityUnusable] }

        var statements: [SummaryStatement] = []
        let stats = facts.statistics

        if stats.totalEventCount == 0 {
            statements.append(.nothingDetected)
        } else if stats.eventsPerHour >= Self.activeEventsPerHour {
            statements.append(.overallActive(eventCount: stats.totalEventCount))
        } else {
            statements.append(.overallCalm)
        }

        if stats.snoringFraction >= Self.significantSnoringFraction {
            if let window = facts.snoringWindow {
                statements.append(.snoringConcentrated(
                    start: window.start,
                    end: window.end,
                    total: stats.snoringDuration
                ))
            } else {
                statements.append(.snoringScattered(total: stats.snoringDuration))
            }
        }

        if stats.coughCount > 0 {
            statements.append(.coughs(count: stats.coughCount))
        }

        if stats.talkingDuration > 0 {
            statements.append(.speech(total: stats.talkingDuration))
        }

        if let loudest = facts.loudestEventDate {
            statements.append(.loudEvent(at: loudest))
        }

        // Only worth naming when the night had enough happening for a quiet
        // stretch to be notable. On an already silent night it says nothing.
        if let calmest = stats.calmestPeriod, stats.totalEventCount > 3 {
            statements.append(.calmestStretch(start: calmest.start, end: calmest.end))
        }

        // Last, and never omitted: a gap the reader does not know about turns
        // every count above it into an undercount.
        if facts.gapCount > 0 {
            statements.append(.interrupted(gapCount: facts.gapCount))
        }

        return statements
    }
}
