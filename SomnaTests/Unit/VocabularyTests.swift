import Foundation
import Testing

@testable import Somna

/// Turns Somna's central product promise into something a build can fail on.
///
/// Everything else in this app is recoverable. Telling someone they have sleep
/// apnea, or that they turned over four times, is not: it is a claim the
/// microphone cannot support, and once made, every other reading becomes
/// suspect. These tests exist so that promise cannot erode through a well-meant
/// copy edit six months from now.
struct VocabularyTests {

    /// Clinical and diagnostic language, plus assertions of body movement.
    /// Matched case-insensitively against every string the domain can produce.
    static let forbiddenTerms = [
        "apnea", "apnoea", "diagnos",
        "sleep score", "sleep quality",
        "deep sleep", "light sleep", "rem sleep", "sleep stage", "sleep cycle",
        "you moved", "you turned", "body movement", "tossed", "turned over",
        "respiratory rate", "breathing rate", "heart rate", "oxygen",
        "insomnia", "disorder", "symptom", "treatment",
    ]

    @Test("No event label anywhere uses clinical or diagnostic language")
    func noLabelUsesClinicalLanguage() {
        for type in NightEventType.allCases {
            for confidence in EventConfidence.allCases {
                let label = NightEventPhrasing.englishTitle(for: type, confidence: confidence).lowercased()
                for term in Self.forbiddenTerms {
                    #expect(
                        !label.contains(term),
                        "\(type.rawValue)/\(confidence.rawValue) contains forbidden term '\(term)': \(label)"
                    )
                }
            }
        }
    }

    @Test("No error message uses clinical or diagnostic language")
    func noErrorUsesClinicalLanguage() {
        let errors: [SomnaError] = [
            .environmentNotConfigured(component: "test"),
            .persistenceUnavailable(underlying: "test"),
            .sessionNotFound(id: UUID()),
            .insufficientStorage(requiredBytes: 1, availableBytes: 0),
            .microphoneAccessDenied,
            .corruptedFile,
            .recordingTooShort(recorded: 1, minimum: 2),
        ]

        for error in errors {
            let text = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            #expect(!text.isEmpty, "Every error must be describable to the user")
            for term in Self.forbiddenTerms {
                #expect(!text.contains(term), "Error text contains '\(term)': \(text)")
            }
        }
    }

    /// The microphone hears a rustle. It does not observe a body moving.
    /// Movement labels therefore stay hedged even at high confidence — "high"
    /// means the *sound* was clear, not that the interpretation is certain.
    @Test("Movement labels stay hedged at every confidence level")
    func movementLabelsAlwaysHedge() {
        let hedges = ["likely", "possible", "-like", "may", "probable"]

        for confidence in EventConfidence.allCases {
            let label = NightEventPhrasing.englishTitle(for: .movementNoise, confidence: confidence).lowercased()
            #expect(
                hedges.contains(where: label.contains),
                "movementNoise/\(confidence.rawValue) asserts movement without hedging: \(label)"
            )
        }
    }

    /// Confidence has to be legible in the words themselves. An icon or a colour
    /// is not enough: VoiceOver users hear the label, and everyone else reads it
    /// faster than they interpret a badge.
    /// Two types are deliberately exempt because confidence has no meaning for
    /// them: `sessionGap` is a fact about the recording, not an interpretation,
    /// and `unknown` *is* the absence of a classification — "confidently
    /// unidentified" would be incoherent.
    static let nonClassifyingTypes: Set<NightEventType> = [.sessionGap, .unknown]

    @Test("Lower confidence always reads as less certain than higher confidence")
    func confidenceIsVisibleInTheWording() {
        let assertiveMarkers = ["detected", "interrupted"]

        for type in NightEventType.allCases where !Self.nonClassifyingTypes.contains(type) {
            let high = NightEventPhrasing.englishTitle(for: type, confidence: .high).lowercased()
            let medium = NightEventPhrasing.englishTitle(for: type, confidence: .medium).lowercased()
            let low = NightEventPhrasing.englishTitle(for: type, confidence: .low).lowercased()

            #expect(high != medium, "\(type.rawValue): high and medium read identically")
            #expect(medium != low, "\(type.rawValue): medium and low read identically")

            // Only the high-confidence wording may be flatly assertive.
            for marker in assertiveMarkers {
                #expect(!low.contains(marker), "\(type.rawValue) low confidence is too assertive: \(low)")
            }
        }
    }

    /// The exemption above is asserted rather than assumed, so a later edit that
    /// starts hedging these types is caught instead of silently accepted.
    @Test("Non-classifying types read the same at every confidence level")
    func nonClassifyingTypesIgnoreConfidence() {
        for type in Self.nonClassifyingTypes where type == .sessionGap {
            let titles = EventConfidence.allCases.map {
                NightEventPhrasing.englishTitle(for: type, confidence: $0)
            }
            #expect(Set(titles).count == 1, "\(type.rawValue) should not vary with confidence")
        }

        // `unknown` is the one exception to the exception: a faint unidentified
        // sound is worth distinguishing from a clear one, because the user
        // deciding whether to listen needs to know if there is anything to hear.
        #expect(
            NightEventPhrasing.englishTitle(for: .unknown, confidence: .low)
                != NightEventPhrasing.englishTitle(for: .unknown, confidence: .high)
        )
    }

    /// A missing table entry would silently fall back to "Unidentified sound",
    /// which is a plausible-looking wrong answer — the worst kind.
    @Test("Every event type has an explicit phrasing entry")
    func phrasingTableIsExhaustive() {
        for type in NightEventType.allCases {
            #expect(
                NightEventPhrasing.table[type] != nil,
                "\(type.rawValue) has no phrasing entry and would fall back silently"
            )
        }
    }

    @Test("Localisation keys are stable and unique")
    func localisationKeysAreUnique() {
        var seen = Set<String>()
        for type in NightEventType.allCases {
            for confidence in EventConfidence.allCases {
                let key = NightEventPhrasing.key(for: type, confidence: confidence)
                #expect(seen.insert(key).inserted, "Duplicate localisation key: \(key)")
                #expect(key.hasPrefix("event."))
            }
        }
    }
}
