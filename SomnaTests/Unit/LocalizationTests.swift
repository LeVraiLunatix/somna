import Foundation
import Testing

@testable import Somna

/// Verifies the String Catalogue actually compiled and shipped, and extends the
/// vocabulary guarantee to French.
///
/// Phase 3A left a hole: `VocabularyTests` only inspected English source
/// strings, because French did not exist yet. A promise that holds in one
/// language and not the other is not a promise — most beta testers will read
/// the French.
struct LocalizationTests {

    /// The French bundle, or `nil` if the catalogue did not compile into the app.
    private var frenchBundle: Bundle? {
        guard let path = Bundle.main.path(forResource: "fr", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private func french(_ key: String) -> String? {
        guard let bundle = frenchBundle else { return nil }
        let sentinel = "<<missing>>"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : value
    }

    @Test("The French localisation is compiled into the app bundle")
    func frenchIsBundled() throws {
        // Fails if the catalogue is missing from the target, or if the project
        // does not declare French as a known region — both silent failures that
        // would otherwise ship an English-only build to French testers.
        _ = try #require(
            frenchBundle,
            "fr.lproj is absent from the app bundle: the String Catalogue did not compile."
        )
    }

    @Test("Event phrasing resolves in French")
    func eventPhrasingResolves() throws {
        try #require(frenchBundle != nil)

        #expect(french("event.coughing.high") == "Toux détectée")
        #expect(french("event.coughing.medium") == "Toux probable")
        #expect(french("event.coughing.low") == "Son ressemblant à une toux")
    }

    /// Same rule as the English side: confidence has to be legible in the words.
    @Test("French wording distinguishes confidence levels")
    func frenchConfidenceIsVisible() throws {
        try #require(frenchBundle != nil)

        let exempt: Set<NightEventType> = [.sessionGap, .unknown]
        for type in NightEventType.allCases where !exempt.contains(type) {
            let high = french(NightEventPhrasing.key(for: type, confidence: .high))
            let medium = french(NightEventPhrasing.key(for: type, confidence: .medium))
            let low = french(NightEventPhrasing.key(for: type, confidence: .low))

            #expect(high != nil, "Missing French for \(type.rawValue) at high confidence")
            #expect(high != medium, "\(type.rawValue): French high and medium read identically")
            #expect(medium != low, "\(type.rawValue): French medium and low read identically")
        }
    }

    /// The French counterpart of `VocabularyTests.forbiddenTerms`.
    ///
    /// Scoped to labels and messages, not to the onboarding disclaimer, which
    /// legitimately contains "diagnostic" in order to deny making one.
    static let forbiddenFrenchTerms = [
        "apnée", "apnee", "diagnostic", "diagnostiqu",
        "score de sommeil", "qualité du sommeil", "qualite du sommeil",
        "sommeil profond", "sommeil léger", "phase de sommeil", "cycle de sommeil",
        "tu t'es retourné", "mouvement corporel", "tu as bougé",
        "fréquence respiratoire", "rythme cardiaque", "saturation",
        "insomnie", "symptôme", "pathologie", "traitement",
    ]

    @Test("No French event label uses clinical language")
    func frenchLabelsAvoidClinicalLanguage() throws {
        try #require(frenchBundle != nil)

        for type in NightEventType.allCases {
            for confidence in EventConfidence.allCases {
                let key = NightEventPhrasing.key(for: type, confidence: confidence)
                guard let label = french(key)?.lowercased() else { continue }

                for term in Self.forbiddenFrenchTerms {
                    #expect(
                        !label.contains(term),
                        "\(key) contains forbidden French term '\(term)': \(label)"
                    )
                }
            }
        }
    }

    /// Movement labels must hedge in French too. "Mouvement audible probable"
    /// is the line; "tu as bougé" is what it must never become.
    @Test("French movement labels stay hedged at every confidence level")
    func frenchMovementStaysHedged() throws {
        try #require(frenchBundle != nil)

        let hedges = ["probable", "possible", "évoquant", "ressemblant", "peut-être"]
        for confidence in EventConfidence.allCases {
            let key = NightEventPhrasing.key(for: .movementNoise, confidence: confidence)
            guard let label = french(key)?.lowercased() else {
                Issue.record("Missing French movement label for \(confidence.rawValue)")
                continue
            }
            #expect(
                hedges.contains(where: label.contains),
                "French movement label asserts movement without hedging: \(label)"
            )
        }
    }

    @Test("Error messages and their remedies are translated")
    func errorsAreTranslated() throws {
        try #require(frenchBundle != nil)

        let keys = [
            "error.microphone.title", "error.microphone.suggestion",
            "error.storage.title", "error.storage.suggestion",
            "audio.sessionUnavailable.title", "audio.sessionUnavailable.suggestion",
        ]
        for key in keys {
            let value = french(key)
            #expect(value != nil, "Missing French translation for \(key)")
            #expect(value?.isEmpty == false)
        }
    }

    @Test("Calibration advice is translated")
    func calibrationAdviceIsTranslated() throws {
        try #require(frenchBundle != nil)

        for issue in CalibrationIssue.allCases {
            let value = french(issue.adviceKey)
            #expect(value != nil, "Missing French advice for \(issue.rawValue)")
        }
    }
}
