import Foundation

/// The result of measuring the room before the first night.
///
/// Every level Somna reports is relative to ``ambientNoiseFloor``. Without a
/// calibration there is no reference, and detections would be compared against
/// an arbitrary constant that happens to suit a quiet bedroom and nothing else.
struct CalibrationProfile: Identifiable, Equatable, Sendable {

    enum Rating: String, Codable, Sendable, CaseIterable {
        case excellent
        case good
        case needsImprovement
    }

    enum DevicePlacement: String, Codable, Sendable, CaseIterable {
        case nightstand
        case bed
        case floor
        case unknown
    }

    let id: UUID

    /// Mean level measured over the calibration window, in normalised units.
    var ambientNoiseFloor: Double

    /// Spread of the measurement. A high value means the room was not actually
    /// quiet during calibration, which makes the floor unreliable.
    var noiseVariability: Double

    /// Reference input gain at calibration time, so a later change in input
    /// route can be detected and the profile invalidated.
    var inputGainReference: Double

    var placement: DevicePlacement
    var rating: Rating
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ambientNoiseFloor: Double,
        noiseVariability: Double = 0,
        inputGainReference: Double = 1,
        placement: DevicePlacement = .unknown,
        rating: Rating,
        createdAt: Date
    ) {
        self.id = id
        self.ambientNoiseFloor = ambientNoiseFloor
        self.noiseVariability = noiseVariability
        self.inputGainReference = inputGainReference
        self.placement = placement
        self.rating = rating
        self.createdAt = createdAt
    }
}

extension CalibrationProfile {

    /// Calibration ages: rooms change, phones move, seasons bring open windows.
    /// After this the user is invited — not forced — to recalibrate.
    static let recommendedRefreshInterval: TimeInterval = 30 * 24 * 3600

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(createdAt) > Self.recommendedRefreshInterval
    }
}
