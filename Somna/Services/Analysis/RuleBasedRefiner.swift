import Foundation

/// Reconciles what the classifier said with what the signal actually looks like.
///
/// The classifier proposes; the rules arbitrate. This exists because a general
/// sound classifier trained on daytime audio is confident in ways that do not
/// survive a bedroom at 3 a.m.: a fan is labelled snoring, a duvet is labelled
/// speech. Every rule here only ever *lowers* confidence or reclassifies to
/// something vaguer — none of them invents a detection the model did not make.
enum RuleBasedRefiner {

    /// Below this rhythm score, an envelope has no breath cycle in it.
    static let snoringPeriodicityFloor = 0.30
    /// Snoring lives in low frequencies, so its zero-crossing rate is low.
    /// A hiss labelled as snoring gives itself away here.
    static let snoringMaximumZeroCrossingRate: Float = 0.28
    /// Speech that is really rustling: broadband, brief, no rhythm.
    static let speechMinimumDuration: TimeInterval = 0.6

    struct Input: Sendable {
        let classification: SoundClassification
        let zone: CandidateZone
        /// Rhythm of the level envelope inside the zone, 0–1.
        let periodicity: Double
    }

    struct Refined: Equatable, Sendable {
        let type: NightEventType
        let confidence: Double
        let start: TimeInterval
        let duration: TimeInterval
        let peak: Float
        /// Set when a rule disagreed with the classifier, for diagnostics.
        let adjustment: Adjustment?

        enum Adjustment: String, Equatable, Sendable {
            case snoringWithoutRhythm
            case snoringTooBright
            case speechTooBrief
            case unclassifiedTransient
        }
    }

    static func refine(_ input: Input) -> Refined {
        let proposed = ClassificationMapping.type(for: input.classification.identifier)
        var type = proposed
        var confidence = input.classification.confidence
        var adjustment: Refined.Adjustment?

        switch proposed {
        case .snoring:
            // Snoring without a breath rhythm is almost always a machine. The
            // detection is not discarded — it really was a low, sustained sound —
            // but it stops being called snoring.
            if input.periodicity < snoringPeriodicityFloor {
                type = .whiteNoise
                confidence = min(confidence, 0.5)
                adjustment = .snoringWithoutRhythm
            } else if input.zone.averageZeroCrossingRate > snoringMaximumZeroCrossingRate {
                confidence *= 0.7
                adjustment = .snoringTooBright
            }

        case .talking:
            // Speech is never a third of a second long. A brief broadband burst
            // labelled speech is far more likely to be bedding.
            if input.zone.duration < speechMinimumDuration {
                type = .beddingNoise
                confidence = min(confidence, 0.45)
                adjustment = .speechTooBrief
            }

        case .unknown:
            // The classifier had nothing. A short, bright, quiet transient is the
            // signature of movement in bed — reported as such, and always with
            // the hedged wording the phrasing table enforces.
            if input.zone.duration < 2,
               input.zone.averageZeroCrossingRate > 0.3,
               input.zone.peak < 0.5 {
                type = .movementNoise
                confidence = min(confidence, 0.45)
                adjustment = .unclassifiedTransient
            }

        default:
            break
        }

        return Refined(
            type: type,
            confidence: confidence,
            start: input.classification.start,
            duration: input.classification.duration,
            peak: input.zone.peak,
            adjustment: adjustment
        )
    }

    /// Turns refined detections into events, dropping anything too weak to show.
    ///
    /// The rejection threshold comes from the user's sensitivity setting, so
    /// "conservative" genuinely means fewer, surer events rather than the same
    /// events with different labels.
    static func makeEvents(
        from refined: [Refined],
        sessionID: UUID,
        sessionStart: Date,
        rejectionThreshold: Double,
        now: Date
    ) -> [NightEvent] {
        refined.compactMap { detection in
            guard detection.confidence >= rejectionThreshold else { return nil }
            guard let confidence = EventConfidence(score: detection.confidence) else { return nil }

            return NightEvent(
                sessionID: sessionID,
                type: detection.type,
                confidence: confidence,
                startDate: sessionStart.addingTimeInterval(detection.start),
                endDate: sessionStart.addingTimeInterval(detection.start + detection.duration),
                peakLevel: Double(detection.peak),
                averageLevel: Double(detection.peak) * 0.6,
                createdAt: now
            )
        }
    }
}
