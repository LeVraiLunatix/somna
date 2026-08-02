import Foundation

/// What a calibration measurement concluded.
struct CalibrationAssessment: Equatable, Sendable {
    let rating: CalibrationProfile.Rating
    let issues: [CalibrationIssue]
    let noiseFloor: Double
    let variability: Double
}

/// Problems a calibration can detect, each with a concrete remedy.
///
/// Every case must be something the user can act on. "Poor placement" with no
/// explanation is a verdict, not advice, and a verdict nobody can act on just
/// makes people distrust the app.
enum CalibrationIssue: String, Sendable, CaseIterable {
    /// No usable signal at all — a covered microphone, or an input that is not
    /// delivering audio.
    case noInput
    case highAmbientNoise
    case unstableEnvironment
    case veryQuietInput
}

/// Turns a window of measured levels into a placement verdict.
///
/// Pure and injectable so it can be tested exhaustively without a microphone —
/// which matters, because the CI runner has no audio input at all.
///
/// Levels are normalised 0–1 relative to full scale, never decibels SPL: an
/// iPhone microphone is not factory calibrated for absolute acoustic
/// measurement, so an SPL figure would be invented.
enum PlacementQualityEvaluator {

    /// A room this quiet gives the classifier a clean signal.
    static let excellentFloor = 0.08
    /// Usable, but faint events will be masked.
    static let acceptableFloor = 0.18
    /// Above this the level swung so much that the floor is not meaningful.
    static let unstableVariability = 0.12
    /// Below this there is effectively no signal reaching the microphone.
    static let silenceThreshold = 0.001

    static func evaluate(levels: [Double]) -> CalibrationAssessment {
        let usable = levels.filter { $0.isFinite && $0 >= 0 }

        guard !usable.isEmpty else {
            return CalibrationAssessment(
                rating: .needsImprovement,
                issues: [.noInput],
                noiseFloor: 0,
                variability: 0
            )
        }

        let floor = median(of: usable)
        let spread = variability(of: usable)
        let peak = usable.max() ?? 0

        // A completely flat, silent window is not a wonderfully quiet bedroom:
        // it is an input delivering nothing. Reporting "excellent" here would
        // send someone to bed with a microphone under a pillow, and they would
        // wake up to an empty timeline that looks like a calm night.
        if peak < silenceThreshold {
            return CalibrationAssessment(
                rating: .needsImprovement,
                issues: [.noInput],
                noiseFloor: floor,
                variability: spread
            )
        }

        var issues: [CalibrationIssue] = []

        if floor > acceptableFloor {
            issues.append(.highAmbientNoise)
        }
        if spread > unstableVariability {
            issues.append(.unstableEnvironment)
        }
        if peak < 0.01 {
            issues.append(.veryQuietInput)
        }

        let rating: CalibrationProfile.Rating
        if issues.isEmpty && floor <= excellentFloor {
            rating = .excellent
        } else if floor <= acceptableFloor && !issues.contains(.veryQuietInput) {
            rating = .good
        } else {
            rating = .needsImprovement
        }

        return CalibrationAssessment(
            rating: rating,
            issues: issues,
            noiseFloor: floor,
            variability: spread
        )
    }

    // MARK: - Statistics

    /// Median rather than mean: a single door slam during calibration would drag
    /// a mean upward and condemn a perfectly good bedroom.
    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Interquartile range rather than standard deviation, for the same reason:
    /// it describes the bulk of the window instead of its outliers.
    private static func variability(of values: [Double]) -> Double {
        guard values.count >= 4 else { return 0 }
        let sorted = values.sorted()
        let lower = sorted[sorted.count / 4]
        let upper = sorted[(sorted.count * 3) / 4]
        return max(0, upper - lower)
    }
}

extension CalibrationIssue {
    /// English source string; the French catalogue entry carries the same key.
    var adviceKey: String { "calibration.issue.\(rawValue)" }

    var englishAdvice: String {
        switch self {
        case .noInput:
            "Somna is not picking up any sound. Check that nothing is covering the bottom of your iPhone."
        case .highAmbientNoise:
            "The room is quite noisy. A fan or an open window will mask quieter sounds."
        case .unstableEnvironment:
            "The noise level kept changing. Try again once the room has settled."
        case .veryQuietInput:
            "The signal is very faint. Move your iPhone closer to the bed."
        }
    }
}
