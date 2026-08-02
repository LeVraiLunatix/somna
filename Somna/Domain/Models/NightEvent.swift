import Foundation

/// One thing Somna heard, placed on the night timeline.
///
/// An event always points at real audio: `clipFileName` is what lets the user
/// verify the claim by ear. An event without a clip is allowed (the clip may
/// have been purged by the retention policy) but is never *created* without one.
struct NightEvent: Identifiable, Equatable, Sendable {

    let id: UUID
    let sessionID: UUID

    /// What the analysis pipeline concluded.
    var type: NightEventType

    /// What the user said it actually was, if they corrected it. Kept separate
    /// from `type` so a correction never overwrites what the model produced —
    /// the pair is exactly the training signal a future model would need.
    var userCorrectedType: NightEventType?

    var confidence: EventConfidence
    var startDate: Date
    var endDate: Date

    /// How many individual detections were merged into this entry.
    ///
    /// Twelve snores in half an hour are one timeline row, not twelve. Keeping
    /// the count means the row can say "12 episodes" without inventing a
    /// separate model for grouped events.
    var occurrenceCount: Int

    /// Peak and mean level, normalised against the calibration noise floor.
    ///
    /// Deliberately not decibels SPL: an iPhone microphone is not factory
    /// calibrated for absolute acoustic measurement, so any dB figure shown to a
    /// user would be a fabrication. These are relative, 0–1, and only ever
    /// rendered as bars, never as numbers with units.
    var peakLevel: Double
    var averageLevel: Double

    /// Downsampled envelope for the mini-waveform, 0–1.
    var waveformSamples: [Float]

    /// File name of the extracted clip, relative to the session's clip folder.
    /// Never an absolute path: absolute paths break when the app container is
    /// relocated, which iOS does on restore and on some updates.
    var clipFileName: String?

    var isFavorite: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        type: NightEventType,
        userCorrectedType: NightEventType? = nil,
        confidence: EventConfidence,
        startDate: Date,
        endDate: Date,
        occurrenceCount: Int = 1,
        peakLevel: Double = 0,
        averageLevel: Double = 0,
        waveformSamples: [Float] = [],
        clipFileName: String? = nil,
        isFavorite: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.type = type
        self.userCorrectedType = userCorrectedType
        self.confidence = confidence
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.occurrenceCount = max(1, occurrenceCount)
        self.peakLevel = peakLevel.clamped(to: 0...1)
        self.averageLevel = averageLevel.clamped(to: 0...1)
        self.waveformSamples = waveformSamples
        self.clipFileName = clipFileName
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}

extension NightEvent {

    /// The type to display and to count in statistics: the user's correction
    /// wins over the model's guess, always.
    var effectiveType: NightEventType {
        userCorrectedType ?? type
    }

    /// A user correction is treated as ground truth, so the hedged wording drops.
    var effectiveConfidence: EventConfidence {
        userCorrectedType == nil ? confidence : .high
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var isGrouped: Bool {
        occurrenceCount > 1
    }

    var hasPlayableClip: Bool {
        clipFileName != nil
    }

    /// The words shown to the user. Routed through ``NightEventPhrasing`` so no
    /// screen can build its own, less careful, sentence.
    var title: String {
        NightEventPhrasing.title(for: effectiveType, confidence: effectiveConfidence)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
