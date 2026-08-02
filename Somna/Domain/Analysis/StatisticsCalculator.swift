import Foundation

/// Turns events into the numbers the report shows.
enum StatisticsCalculator {

    /// Level above which an event is called loud. Relative to full scale, like
    /// every other level in Somna — never decibels SPL.
    static let loudPeakThreshold = 0.7

    static func statistics(
        events: [NightEvent],
        session: NightSession,
        calendar: Calendar
    ) -> NightStatistics {

        // Session gaps are bookkeeping, not detections. Counting them as events
        // would make an interrupted night look busier than it was.
        let detections = events.filter { $0.effectiveType != .sessionGap }

        var counts: [NightEventType: Int] = [:]
        for event in detections {
            counts[event.effectiveType, default: 0] += event.occurrenceCount
        }

        let snoring = detections.filter { $0.effectiveType == .snoring }
        let talking = detections.filter { $0.effectiveType == .talking }

        let soundedDuration = detections.reduce(0) { $0 + $1.duration }
        let quiet = max(0, session.recordedDuration - soundedDuration)

        return NightStatistics(
            recordedDuration: session.recordedDuration,
            quietDuration: quiet,
            snoringDuration: snoring.reduce(0) { $0 + $1.duration },
            coughCount: counts[.coughing] ?? 0,
            talkingDuration: talking.reduce(0) { $0 + $1.duration },
            loudEventCount: detections.filter { $0.peakLevel >= loudPeakThreshold }.count,
            totalEventCount: detections.reduce(0) { $0 + $1.occurrenceCount },
            eventCountsByType: counts,
            calmestPeriod: calmestPeriod(events: detections, session: session),
            busiestHour: busiestHour(events: detections, calendar: calendar)
        )
    }

    /// The longest stretch with nothing detected.
    ///
    /// Only returned when it is long enough to mean something: a two-minute gap
    /// between snores is not a calm period, and calling it one would be the kind
    /// of false precision this app avoids.
    static func calmestPeriod(events: [NightEvent], session: NightSession) -> DateInterval? {
        guard let end = session.endDate else { return nil }

        let sorted = events.sorted { $0.startDate < $1.startDate }
        var cursor = session.startDate
        var best: DateInterval?

        for event in sorted {
            if event.startDate > cursor {
                let candidate = DateInterval(start: cursor, end: event.startDate)
                if candidate.duration > (best?.duration ?? 0) { best = candidate }
            }
            cursor = max(cursor, event.endDate)
        }

        if end > cursor {
            let candidate = DateInterval(start: cursor, end: end)
            if candidate.duration > (best?.duration ?? 0) { best = candidate }
        }

        guard let best, best.duration >= AnalysisConstants.minimumCalmPeriod else { return nil }
        return best
    }

    /// Start of the hour holding the most events.
    static func busiestHour(events: [NightEvent], calendar: Calendar) -> Date? {
        guard !events.isEmpty else { return nil }

        var buckets: [Date: Int] = [:]
        for event in events {
            let hour = calendar.dateInterval(of: .hour, for: event.startDate)?.start ?? event.startDate
            buckets[hour, default: 0] += event.occurrenceCount
        }

        // Ties resolve to the earlier hour so the same night always reports the
        // same figure — a statistic that moves between runs is not a statistic.
        return buckets
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .first?
            .key
    }
}

/// Estimates when sleep probably began and ended.
///
/// Acoustic only, and stated as such everywhere it surfaces. Somna sees a long
/// quiet stretch; it does not see sleep. When the evidence is weak the estimate
/// is **omitted entirely** rather than shown with a caveat nobody reads.
enum SleepWindowEstimator {

    struct Estimate: Equatable, Sendable {
        let sleepStart: Date?
        let wakeTime: Date?
    }

    static func estimate(
        events: [NightEvent],
        session: NightSession,
        minimumCalm: TimeInterval = AnalysisConstants.minimumCalmPeriod
    ) -> Estimate {
        guard
            let end = session.endDate,
            session.isAnalysable
        else { return Estimate(sleepStart: nil, wakeTime: nil) }

        let detections = events
            .filter { $0.effectiveType != .sessionGap }
            .sorted { $0.startDate < $1.startDate }

        let quietStretches = quietStretches(
            events: detections,
            from: session.startDate,
            to: end,
            minimum: minimumCalm
        )

        guard let first = quietStretches.first, let last = quietStretches.last else {
            // A night with no sustained quiet says nothing about falling asleep.
            return Estimate(sleepStart: nil, wakeTime: nil)
        }

        // Falling asleep is the beginning of the first long quiet stretch; waking
        // is the end of the last one. Both are only offered when the stretch
        // actually starts after, and ends before, the session bounds — otherwise
        // the "estimate" is just the session itself wearing a different label.
        let sleepStart = first.start > session.startDate ? first.start : nil
        let wakeTime = last.end < end ? last.end : nil

        return Estimate(sleepStart: sleepStart, wakeTime: wakeTime)
    }

    private static func quietStretches(
        events: [NightEvent],
        from start: Date,
        to end: Date,
        minimum: TimeInterval
    ) -> [DateInterval] {
        var stretches: [DateInterval] = []
        var cursor = start

        for event in events {
            if event.startDate > cursor {
                let candidate = DateInterval(start: cursor, end: event.startDate)
                if candidate.duration >= minimum { stretches.append(candidate) }
            }
            cursor = max(cursor, event.endDate)
        }

        if end > cursor {
            let candidate = DateInterval(start: cursor, end: end)
            if candidate.duration >= minimum { stretches.append(candidate) }
        }

        return stretches
    }
}
