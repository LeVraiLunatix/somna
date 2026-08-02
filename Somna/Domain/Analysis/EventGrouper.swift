import Foundation

/// Merges repetitive detections into single timeline entries.
///
/// Twelve snores in half an hour are one row saying "12 episodes", not twelve
/// rows. Without this the timeline of a snoring night is unreadable, and the
/// events that actually matter — a cough, a door — are buried under repetition.
enum EventGrouper {

    /// Groups events of the same kind that fall within
    /// ``AnalysisConstants/groupingWindow`` of each other.
    ///
    /// Grouping uses `effectiveType`, so a user correction re-groups the event
    /// with what they said it was rather than with what the model guessed.
    static func group(
        _ events: [NightEvent],
        window: TimeInterval = AnalysisConstants.groupingWindow
    ) -> [NightEvent] {
        guard !events.isEmpty else { return [] }

        let sorted = events.sorted { $0.startDate < $1.startDate }
        var result: [NightEvent] = []

        for event in sorted {
            guard
                let index = result.lastIndex(where: { canMerge($0, event, window: window) })
            else {
                result.append(event)
                continue
            }
            result[index] = merge(result[index], event)
        }

        return result
    }

    private static func canMerge(
        _ existing: NightEvent,
        _ candidate: NightEvent,
        window: TimeInterval
    ) -> Bool {
        guard existing.effectiveType == candidate.effectiveType else { return false }

        // Gaps in the recording are facts about the session, not detections:
        // merging two interruptions would hide that there were two.
        guard existing.effectiveType != .sessionGap else { return false }

        return candidate.startDate.timeIntervalSince(existing.endDate) <= window
    }

    private static func merge(_ existing: NightEvent, _ candidate: NightEvent) -> NightEvent {
        var merged = existing

        merged.endDate = max(existing.endDate, candidate.endDate)
        merged.occurrenceCount = existing.occurrenceCount + candidate.occurrenceCount

        // The group is as confident as its strongest member: if one snore in a
        // bout was unmistakable, the bout was snoring.
        merged.confidence = max(existing.confidence, candidate.confidence)

        merged.peakLevel = max(existing.peakLevel, candidate.peakLevel)
        merged.averageLevel = (existing.averageLevel + candidate.averageLevel) / 2

        // The group keeps the clip of its loudest member, which is the one worth
        // listening to when checking whether the classification was right.
        if candidate.peakLevel > existing.peakLevel, candidate.clipFileName != nil {
            merged.clipFileName = candidate.clipFileName
            merged.waveformSamples = candidate.waveformSamples
        }

        // A favourite anywhere in the group survives the merge.
        merged.isFavorite = existing.isFavorite || candidate.isFavorite

        return merged
    }
}
