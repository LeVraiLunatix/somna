import Foundation
import SwiftData

// Persistence models. Prefixed `SD` so any leak of a storage type into the
// domain or a view is visible in a diff.
//
// Two conventions apply throughout:
//
// * **Enums are stored as raw strings, not as Codable enums.** SwiftData can
//   persist Codable enums, but adding or renaming a case then risks failing to
//   decode existing rows. A string plus a lenient mapper degrades to a known
//   fallback instead of losing a night.
// * **No absolute file paths.** iOS relocates the app container on restore and
//   on some updates, which invalidates every stored absolute URL. Only file
//   names are persisted; `NightFileStore` resolves them at read time.

@Model
final class SDNightSession {

    #Unique<SDNightSession>([\.id])
    #Index<SDNightSession>([\.startDate])

    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date?
    var statusRaw: String = NightSessionStatus.recording.rawValue
    var recordedDuration: TimeInterval = 0
    var estimatedSleepStart: Date?
    var estimatedWakeTime: Date?
    var calmnessScore: Int?

    // Encoded rather than modelled: neither statements nor statistics are ever
    // queried or sorted on, and flattening them into columns would add a dozen
    // fields that only ever move together.
    @Attribute(.externalStorage)
    var summaryStatementsData: Data?
    var statisticsData: Data?

    var qualityRatingRaw: String?
    var qualityIssuesRaw: [String] = []
    var qualityAverageNoiseFloor: Double = 0
    var qualityCoverage: Double = 1

    var analysisVersion: String = AnalysisConstants.currentVersion
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SDNightEvent.session)
    var events: [SDNightEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \SDAudioSegment.session)
    var segments: [SDAudioSegment]? = []

    init(id: UUID, startDate: Date, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.startDate = startDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SDNightEvent {

    #Unique<SDNightEvent>([\.id])
    #Index<SDNightEvent>([\.startDate])

    var id: UUID = UUID()
    var typeRaw: String = NightEventType.unknown.rawValue
    var userCorrectedTypeRaw: String?
    var confidenceRaw: String = EventConfidence.low.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()
    var occurrenceCount: Int = 1
    var peakLevel: Double = 0
    var averageLevel: Double = 0

    /// Externally stored: a night can hold hundreds of events and inlining their
    /// envelopes would bloat every fetch that does not need them.
    @Attribute(.externalStorage)
    var waveformData: Data?

    var clipFileName: String?
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    var session: SDNightSession?

    init(id: UUID, startDate: Date, endDate: Date, createdAt: Date) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }
}

@Model
final class SDAudioSegment {

    #Unique<SDAudioSegment>([\.id])

    var id: UUID = UUID()
    var fileName: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var sampleRate: Double = AudioConstants.sampleRate
    var channelCount: Int = AudioConstants.channelCount
    var fileSize: Int64 = 0
    var processingStateRaw: String = AudioSegment.ProcessingState.recording.rawValue
    var retentionStateRaw: String = AudioSegment.RetentionState.present.rawValue

    var session: SDNightSession?

    init(id: UUID, fileName: String, startDate: Date, endDate: Date) {
        self.id = id
        self.fileName = fileName
        self.startDate = startDate
        self.endDate = endDate
    }
}

@Model
final class SDCalibrationProfile {

    #Unique<SDCalibrationProfile>([\.id])

    var id: UUID = UUID()
    var ambientNoiseFloor: Double = 0
    var noiseVariability: Double = 0
    var inputGainReference: Double = 1
    var placementRaw: String = CalibrationProfile.DevicePlacement.unknown.rawValue
    var ratingRaw: String = CalibrationProfile.Rating.good.rawValue
    var createdAt: Date = Date()

    init(id: UUID, ambientNoiseFloor: Double, createdAt: Date) {
        self.id = id
        self.ambientNoiseFloor = ambientNoiseFloor
        self.createdAt = createdAt
    }
}
