import Foundation

/// A stretch of the night worth looking at closely.
struct CandidateZone: Equatable, Sendable {
    /// Offsets from the start of the session, in seconds.
    let start: TimeInterval
    let end: TimeInterval
    let peak: Float
    let averageLevel: Float
    let averageZeroCrossingRate: Float

    var duration: TimeInterval { max(0, end - start) }

    func overlaps(_ other: ClosedRange<TimeInterval>) -> Bool {
        start <= other.upperBound && end >= other.lowerBound
    }
}

/// Decides which parts of a night deserve the expensive pass.
///
/// A calm night is mostly silence. Running a classifier over eight hours of it
/// would spend minutes of a phone's morning to conclude that nothing happened.
/// This reads the cheap metrics written during the night and hands back the few
/// percent where something did.
enum CandidateSelector {

    /// Detections must clear the room's own floor by this factor before being
    /// worth looking at. Multiplicative rather than additive so it adapts: a
    /// noisy room needs a bigger jump, a silent one needs less.
    static let floorMultiplier = 2.5
    /// Absolute minimum rise, for rooms so quiet that the multiplier alone would
    /// trigger on the microphone's own noise.
    static let minimumRise = 0.012

    /// Windows closer than this are one event, not two.
    static let mergeGap: TimeInterval = 1.5
    /// Below this, it is a click, not something worth a timeline row.
    static let minimumDuration: TimeInterval = 0.3
    /// Context kept either side, so a classifier sees the onset of a sound
    /// rather than starting halfway through it.
    static let padding: TimeInterval = 0.5

    /// Ceiling on how much of a night gets the expensive pass.
    ///
    /// Without it, a night with a fan running would mark everything as a
    /// candidate and the morning analysis would take as long as the night did.
    /// When the budget is exceeded the loudest zones win, because those are the
    /// ones a user would have noticed too.
    static let maximumFraction = 0.20

    static func select(
        metrics: [AudioMetrics],
        noiseFloor: Double,
        sensitivityOffset: Double = 0,
        totalDuration: TimeInterval
    ) -> [CandidateZone] {
        guard !metrics.isEmpty else { return [] }

        let sorted = metrics.sorted { $0.offset < $1.offset }
        let threshold = Float(max(
            noiseFloor * floorMultiplier,
            noiseFloor + minimumRise
        ) + sensitivityOffset)

        var zones: [CandidateZone] = []
        var current: [AudioMetrics] = []

        for sample in sorted {
            if sample.rms >= threshold {
                current.append(sample)
                continue
            }

            // A sample below threshold closes the run only if the silence has
            // actually lasted; otherwise a dip between two snores would split
            // one event in two.
            if let last = current.last, sample.offset - last.offset <= mergeGap {
                continue
            }

            if let zone = makeZone(from: current) { zones.append(zone) }
            current = []
        }

        if let zone = makeZone(from: current) { zones.append(zone) }

        return applyBudget(to: zones, totalDuration: totalDuration)
    }

    private static func makeZone(from samples: [AudioMetrics]) -> CandidateZone? {
        guard let first = samples.first, let last = samples.last else { return nil }

        let start = max(0, first.offset - padding)
        let end = last.offset + padding
        guard end - start >= minimumDuration else { return nil }

        let count = Float(samples.count)
        return CandidateZone(
            start: start,
            end: end,
            peak: samples.map(\.peak).max() ?? 0,
            averageLevel: samples.reduce(0) { $0 + $1.rms } / count,
            averageZeroCrossingRate: samples.reduce(0) { $0 + $1.zeroCrossingRate } / count
        )
    }

    private static func applyBudget(
        to zones: [CandidateZone],
        totalDuration: TimeInterval
    ) -> [CandidateZone] {
        guard totalDuration > 0 else { return zones }

        let budget = totalDuration * maximumFraction
        let total = zones.reduce(0) { $0 + $1.duration }
        guard total > budget else { return zones }

        var kept: [CandidateZone] = []
        var used: TimeInterval = 0

        for zone in zones.sorted(by: { $0.peak > $1.peak }) {
            guard used + zone.duration <= budget else { continue }
            kept.append(zone)
            used += zone.duration
        }

        // Chronological order is restored: everything downstream assumes it.
        return kept.sorted { $0.start < $1.start }
    }
}

/// Measures how regularly a level envelope repeats.
///
/// Snoring has a rhythm — one cycle every two to six seconds, following the
/// breath. Nothing else Somna listens for does. This is what lets the refiner
/// disagree with a classifier that labelled a fan or a distant engine as
/// snoring, and it works on the cheap metrics already written during the night
/// rather than needing a spectrum.
enum EnvelopePeriodicity {

    /// The band a human breath cycle falls in.
    static let periodRange: ClosedRange<TimeInterval> = 2...6

    /// - Returns: 0–1. Above roughly 0.35 the envelope has a real rhythm.
    static func strength(
        levels: [Float],
        sampleInterval: TimeInterval
    ) -> Double {
        guard sampleInterval > 0, levels.count >= 8 else { return 0 }

        let mean = levels.reduce(0, +) / Float(levels.count)
        let centred = levels.map { $0 - mean }

        let energy = centred.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return 0 }

        let minimumLag = max(1, Int((periodRange.lowerBound / sampleInterval).rounded()))
        let maximumLag = min(centred.count - 1, Int((periodRange.upperBound / sampleInterval).rounded()))
        guard minimumLag < maximumLag else { return 0 }

        var best: Float = 0
        for lag in minimumLag...maximumLag {
            var correlation: Float = 0
            for index in 0..<(centred.count - lag) {
                correlation += centred[index] * centred[index + lag]
            }
            best = max(best, correlation / energy)
        }

        return Double(min(max(best, 0), 1))
    }
}
