import Foundation

/// The kinds of event Somna can place on a night timeline.
///
/// Extensible by design: a raw-value enum with an `unknown` fallback means a
/// future analysis model can emit a class this build does not know about without
/// breaking decoding of stored nights.
enum NightEventType: String, Codable, CaseIterable, Sendable {

    // Sounds made by a sleeper. Somna never attributes these to a named person:
    // with two people in a room the microphone cannot tell them apart.
    case snoring
    case coughing
    case talking
    case breathing
    case sighing

    // Sounds that *accompany* movement. These are the ones most at risk of being
    // overclaimed, so their phrasing is constrained in `NightEventPhrasing`.
    case movementNoise
    case beddingNoise

    // The room and the world outside it.
    case alarm
    case door
    case animal
    case traffic
    case rain
    case whiteNoise
    case television
    case impact

    // Session bookkeeping, not a detection: a gap is an interruption Somna
    // refuses to hide, because a silent gap would otherwise read as a calm night.
    case sessionGap

    case unknown
}

extension NightEventType {

    /// Grouping used for filters and statistics.
    enum Category: String, Sendable, CaseIterable {
        case sleeper
        case movement
        case environment
        case session
    }

    var category: Category {
        switch self {
        case .snoring, .coughing, .talking, .breathing, .sighing:
            .sleeper
        case .movementNoise, .beddingNoise:
            .movement
        case .alarm, .door, .animal, .traffic, .rain, .whiteNoise, .television, .impact, .unknown:
            .environment
        case .sessionGap:
            .session
        }
    }

    /// SF Symbol used across the timeline, report and history.
    var symbolName: String {
        switch self {
        case .snoring: "zzz"
        case .coughing: "lungs"
        case .talking: "text.bubble"
        case .breathing: "wind"
        case .sighing: "aqi.low"
        case .movementNoise: "arrow.left.arrow.right"
        case .beddingNoise: "bed.double"
        case .alarm: "alarm"
        case .door: "door.left.hand.open"
        case .animal: "pawprint"
        case .traffic: "car"
        case .rain: "cloud.rain"
        case .whiteNoise: "waveform"
        case .television: "tv"
        case .impact: "burst"
        case .sessionGap: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }

    /// Types the user can meaningfully reclassify an event into.
    ///
    /// `sessionGap` is excluded: it is a fact about the recording, not an
    /// interpretation, so there is nothing to correct.
    static var userCorrectable: [NightEventType] {
        allCases.filter { $0 != .sessionGap }
    }
}
