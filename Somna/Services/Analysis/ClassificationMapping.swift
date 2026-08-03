import Foundation
import OSLog

/// What a classifier said about a stretch of audio.
struct SoundClassification: Equatable, Sendable {
    /// The classifier's own label, kept verbatim so unmapped ones can be logged
    /// and the table improved from real nights rather than from guesses.
    let identifier: String
    let confidence: Double
    /// Offsets from the start of the session, in seconds.
    let start: TimeInterval
    let duration: TimeInterval
}

protocol SoundClassifying: Sendable {
    func classify(fileURL: URL, offset: TimeInterval) async throws -> [SoundClassification]
    /// Labels this build's classifier can actually emit.
    func availableIdentifiers() async -> [String]
}

/// Maps a classifier's labels onto Somna's event types.
///
/// **Matching is by substring, not equality.** Apple's label set is not a
/// published contract: names differ between OS versions, and a label may be
/// `door` on one and `door_open_or_close` on another. Exact matching would make
/// a point release silently stop detecting doors — a regression nobody would see
/// until a user asked why their door stopped appearing.
///
/// Anything unmatched becomes `.unknown` and is logged, so the table can be
/// improved from what real nights actually produce.
enum ClassificationMapping {

    /// Ordered: the first pattern that matches wins, so specific patterns must
    /// come before general ones. `alarm_clock` has to be tested before `clock`,
    /// and `snoring` before `breathing`.
    static let rules: [(patterns: [String], type: NightEventType)] = [
        (["snor"], .snoring),
        (["cough"], .coughing),
        (["sneeze", "sniff", "throat_clearing"], .coughing),
        (["alarm", "siren", "beep", "buzzer"], .alarm),
        (["speech", "shout", "whisper", "conversation", "yell", "babble", "singing"], .talking),
        (["sigh", "groan", "moan", "gasp"], .sighing),
        (["breath"], .breathing),
        (["door", "knock", "slam"], .door),
        (["television", "tv_", "radio", "music"], .television),
        (["rain", "thunder", "storm"], .rain),
        (["dog", "cat_", "meow", "bark", "bird", "purr", "animal", "rooster"], .animal),
        (["car", "truck", "traffic", "engine", "motorcycle", "vehicle", "aircraft", "train"], .traffic),
        (["fan_", "air_conditioner", "hum", "white_noise", "static", "vacuum"], .whiteNoise),
        (["glass", "crash", "bang", "thud", "clatter", "boom", "impact"], .impact),
        (["rustl", "fabric", "cloth", "sheet"], .beddingNoise),
        (["footstep", "shuffl", "scrape"], .movementNoise),
    ]

    /// Labels Somna most wants to exist. Checked once against what the
    /// classifier actually offers, so a missing one is discovered at launch
    /// rather than inferred from a night with no snoring in it.
    static let expectedPatterns = ["snor", "cough", "speech", "breath"]

    static func type(for identifier: String) -> NightEventType {
        let normalised = identifier.lowercased()

        for rule in rules where rule.patterns.contains(where: normalised.contains) {
            return rule.type
        }
        return .unknown
    }

    /// Reports which of the labels Somna relies on are missing from this build's
    /// classifier.
    ///
    /// Called once at analysis time. A missing pattern is logged, not fatal: the
    /// rest of the pipeline still works, and a night that detects fewer kinds of
    /// sound is far better than one that fails.
    static func missingExpectedPatterns(in identifiers: [String]) -> [String] {
        let normalised = identifiers.map { $0.lowercased() }
        return expectedPatterns.filter { pattern in
            !normalised.contains { $0.contains(pattern) }
        }
    }

    /// Records a label no rule matched, so the table can be extended from real
    /// data. Only labels the classifier was confident about are worth logging;
    /// the rest are noise.
    static func noteUnmapped(_ identifier: String, confidence: Double) {
        guard confidence >= 0.6 else { return }
        // The label itself is not user data — it is a class name from Apple's
        // model — so it is safe to log in the clear, and useless otherwise.
        Log.analysis.info("Unmapped sound class: \(identifier, privacy: .public)")
    }
}
