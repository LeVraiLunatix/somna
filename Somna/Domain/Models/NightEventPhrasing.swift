import Foundation

/// The words Somna is allowed to use about a detection.
///
/// This table is the product promise made executable. Three rules hold for every
/// entry, and `ConfidenceLabelTests` enforces them:
///
/// 1. **Confidence is visible in the wording, not just in an icon.** A medium
///    detection reads "Likely cough", never "Cough".
/// 2. **No entry asserts body movement.** The microphone hears a rustle; it does
///    not know that someone turned over. `movementNoise` and `beddingNoise` stay
///    hedged even at high confidence.
/// 3. **No entry uses clinical vocabulary.** No apnea, no diagnosis, no sleep
///    stage, no breathing rate.
///
/// Localisation note: keys are built at runtime (`event.<type>.<confidence>`),
/// so Xcode's string extraction cannot see them. The English strings below are
/// therefore the source of truth, and Phase 4 generates the String Catalogue
/// entries from this table — which is also why the table must stay exhaustive.
enum NightEventPhrasing {

    /// Localisation key for a given detection.
    static func key(for type: NightEventType, confidence: EventConfidence) -> String {
        "event.\(type.rawValue).\(confidence.rawValue)"
    }

    /// The user-facing title, localised when a catalogue entry exists and
    /// falling back to the English source string otherwise.
    static func title(for type: NightEventType, confidence: EventConfidence) -> String {
        String.localized(
            dynamicKey: key(for: type, confidence: confidence),
            fallback: englishTitle(for: type, confidence: confidence)
        )
    }

    /// The English source string. Exposed for testing and for catalogue
    /// generation; UI code should call ``title(for:confidence:)``.
    static func englishTitle(for type: NightEventType, confidence: EventConfidence) -> String {
        let phrasing = table[type] ?? Phrasing(
            high: "Unidentified sound",
            medium: "Unidentified sound",
            low: "Faint unidentified sound"
        )
        switch confidence {
        case .high: return phrasing.high
        case .medium: return phrasing.medium
        case .low: return phrasing.low
        }
    }

    struct Phrasing: Sendable {
        let high: String
        let medium: String
        let low: String
    }

    // MARK: - The table

    static let table: [NightEventType: Phrasing] = [

        // Sleeper sounds. Note that none of these say "you": with two people in
        // a bedroom, the microphone cannot attribute a sound to a person.
        .snoring: Phrasing(
            high: "Snoring detected",
            medium: "Likely snoring",
            low: "Snoring-like sound"
        ),
        .coughing: Phrasing(
            high: "Cough detected",
            medium: "Likely cough",
            low: "Cough-like sound"
        ),
        .talking: Phrasing(
            high: "Speech detected",
            medium: "Likely speech",
            low: "Speech-like sound"
        ),
        .breathing: Phrasing(
            high: "Audible breathing",
            medium: "Likely audible breathing",
            low: "Breathing-like sound"
        ),
        .sighing: Phrasing(
            high: "Sigh detected",
            medium: "Likely sigh",
            low: "Sigh-like sound"
        ),

        // Movement. Hedged at every level on purpose: Somna heard something, it
        // did not observe a body moving. Even "high confidence" here means the
        // *sound* was clear, not that the interpretation is certain.
        .movementNoise: Phrasing(
            high: "Audible movement likely",
            medium: "Possible audible movement",
            low: "Faint movement-like sound"
        ),
        .beddingNoise: Phrasing(
            high: "Bedding noise detected",
            medium: "Likely bedding noise",
            low: "Rustling-like sound"
        ),

        // Environment.
        .alarm: Phrasing(
            high: "Alarm detected",
            medium: "Likely alarm",
            low: "Alarm-like sound"
        ),
        .door: Phrasing(
            high: "Door detected",
            medium: "Likely door",
            low: "Door-like sound"
        ),
        .animal: Phrasing(
            high: "Animal detected",
            medium: "Likely animal",
            low: "Animal-like sound"
        ),
        .traffic: Phrasing(
            high: "Traffic detected",
            medium: "Likely traffic",
            low: "Traffic-like sound"
        ),
        .rain: Phrasing(
            high: "Rain detected",
            medium: "Likely rain",
            low: "Rain-like sound"
        ),
        .whiteNoise: Phrasing(
            high: "Steady background noise",
            medium: "Likely steady background noise",
            low: "Faint steady noise"
        ),
        .television: Phrasing(
            high: "Television or media detected",
            medium: "Likely television or media",
            low: "Media-like sound"
        ),
        .impact: Phrasing(
            high: "Loud impact detected",
            medium: "Likely impact",
            low: "Impact-like sound"
        ),

        // Bookkeeping. Not a detection, so confidence does not change the wording:
        // the recording either stopped or it did not.
        .sessionGap: Phrasing(
            high: "Recording interrupted",
            medium: "Recording interrupted",
            low: "Recording interrupted"
        ),

        .unknown: Phrasing(
            high: "Unidentified sound",
            medium: "Unidentified sound",
            low: "Faint unidentified sound"
        ),
    ]
}
