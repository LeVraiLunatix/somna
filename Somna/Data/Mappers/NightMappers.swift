import Foundation

/// Translation between persistence models and domain models.
///
/// Every `rawValue` decode is lenient: an unrecognised string falls back to a
/// safe case instead of throwing. A single unknown enum value — from a build
/// that wrote a case this build does not have — must never make a whole night
/// unreadable.
enum NightSessionMapper {

    static func toDomain(_ model: SDNightSession) -> NightSession {
        NightSession(
            id: model.id,
            startDate: model.startDate,
            endDate: model.endDate,
            status: NightSessionStatus(rawValue: model.statusRaw) ?? .interrupted,
            recordedDuration: model.recordedDuration,
            estimatedSleepStart: model.estimatedSleepStart,
            estimatedWakeTime: model.estimatedWakeTime,
            calmnessScore: model.calmnessScore,
            summaryStatements: decode([SummaryStatement].self, from: model.summaryStatementsData) ?? [],
            statistics: decode(NightStatistics.self, from: model.statisticsData),
            recordingQuality: quality(from: model),
            analysisVersion: model.analysisVersion,
            isFavorite: model.isFavorite,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    /// Copies domain values onto an existing persistence model.
    ///
    /// `id`, `startDate` and `createdAt` are intentionally not written: they are
    /// set once at insertion and rewriting them would let a bug silently
    /// re-identify or re-date an existing night.
    static func apply(_ session: NightSession, to model: SDNightSession) {
        model.endDate = session.endDate
        model.statusRaw = session.status.rawValue
        model.recordedDuration = session.recordedDuration
        model.estimatedSleepStart = session.estimatedSleepStart
        model.estimatedWakeTime = session.estimatedWakeTime
        model.calmnessScore = session.calmnessScore
        model.summaryStatementsData = encode(session.summaryStatements)
        model.statisticsData = session.statistics.flatMap(encode)
        model.analysisVersion = session.analysisVersion
        model.isFavorite = session.isFavorite
        model.updatedAt = session.updatedAt

        model.qualityRatingRaw = session.recordingQuality?.rating.rawValue
        model.qualityIssuesRaw = session.recordingQuality?.issues.map(\.rawValue) ?? []
        model.qualityAverageNoiseFloor = session.recordingQuality?.averageNoiseFloor ?? 0
        model.qualityCoverage = session.recordingQuality?.coverage ?? 1
    }

    static func makeModel(from session: NightSession) -> SDNightSession {
        let model = SDNightSession(
            id: session.id,
            startDate: session.startDate,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
        apply(session, to: model)
        return model
    }

    /// Decoding failures degrade to absence rather than throwing: a summary
    /// written by a future build must not make a night unreadable today.
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func quality(from model: SDNightSession) -> RecordingQuality? {
        guard
            let ratingRaw = model.qualityRatingRaw,
            let rating = RecordingQualityRating(rawValue: ratingRaw)
        else { return nil }

        return RecordingQuality(
            rating: rating,
            issues: model.qualityIssuesRaw.compactMap(RecordingIssue.init(rawValue:)),
            averageNoiseFloor: model.qualityAverageNoiseFloor,
            coverage: model.qualityCoverage
        )
    }
}

enum NightEventMapper {

    static func toDomain(_ model: SDNightEvent, sessionID: UUID) -> NightEvent {
        NightEvent(
            id: model.id,
            sessionID: sessionID,
            type: NightEventType(rawValue: model.typeRaw) ?? .unknown,
            userCorrectedType: model.userCorrectedTypeRaw.flatMap(NightEventType.init(rawValue:)),
            confidence: EventConfidence(rawValue: model.confidenceRaw) ?? .low,
            startDate: model.startDate,
            endDate: model.endDate,
            occurrenceCount: model.occurrenceCount,
            peakLevel: model.peakLevel,
            averageLevel: model.averageLevel,
            waveformSamples: WaveformCoding.decode(model.waveformData),
            clipFileName: model.clipFileName,
            isFavorite: model.isFavorite,
            createdAt: model.createdAt
        )
    }

    static func apply(_ event: NightEvent, to model: SDNightEvent) {
        model.typeRaw = event.type.rawValue
        model.userCorrectedTypeRaw = event.userCorrectedType?.rawValue
        model.confidenceRaw = event.confidence.rawValue
        model.endDate = event.endDate
        model.occurrenceCount = event.occurrenceCount
        model.peakLevel = event.peakLevel
        model.averageLevel = event.averageLevel
        model.waveformData = WaveformCoding.encode(event.waveformSamples)
        model.clipFileName = event.clipFileName
        model.isFavorite = event.isFavorite
    }

    static func makeModel(from event: NightEvent) -> SDNightEvent {
        let model = SDNightEvent(
            id: event.id,
            startDate: event.startDate,
            endDate: event.endDate,
            createdAt: event.createdAt
        )
        apply(event, to: model)
        return model
    }
}

enum AudioSegmentMapper {

    static func toDomain(_ model: SDAudioSegment, sessionID: UUID) -> AudioSegment {
        AudioSegment(
            id: model.id,
            sessionID: sessionID,
            fileName: model.fileName,
            startDate: model.startDate,
            endDate: model.endDate,
            sampleRate: model.sampleRate,
            channelCount: model.channelCount,
            fileSize: model.fileSize,
            processingState: AudioSegment.ProcessingState(rawValue: model.processingStateRaw) ?? .corrupted,
            retentionState: AudioSegment.RetentionState(rawValue: model.retentionStateRaw) ?? .purged
        )
    }

    static func apply(_ segment: AudioSegment, to model: SDAudioSegment) {
        model.fileName = segment.fileName
        model.endDate = segment.endDate
        model.sampleRate = segment.sampleRate
        model.channelCount = segment.channelCount
        model.fileSize = segment.fileSize
        model.processingStateRaw = segment.processingState.rawValue
        model.retentionStateRaw = segment.retentionState.rawValue
    }

    static func makeModel(from segment: AudioSegment) -> SDAudioSegment {
        let model = SDAudioSegment(
            id: segment.id,
            fileName: segment.fileName,
            startDate: segment.startDate,
            endDate: segment.endDate
        )
        apply(segment, to: model)
        return model
    }
}

enum CalibrationMapper {

    static func toDomain(_ model: SDCalibrationProfile) -> CalibrationProfile {
        CalibrationProfile(
            id: model.id,
            ambientNoiseFloor: model.ambientNoiseFloor,
            noiseVariability: model.noiseVariability,
            inputGainReference: model.inputGainReference,
            placement: CalibrationProfile.DevicePlacement(rawValue: model.placementRaw) ?? .unknown,
            rating: CalibrationProfile.Rating(rawValue: model.ratingRaw) ?? .good,
            createdAt: model.createdAt
        )
    }

    static func makeModel(from profile: CalibrationProfile) -> SDCalibrationProfile {
        let model = SDCalibrationProfile(
            id: profile.id,
            ambientNoiseFloor: profile.ambientNoiseFloor,
            createdAt: profile.createdAt
        )
        model.noiseVariability = profile.noiseVariability
        model.inputGainReference = profile.inputGainReference
        model.placementRaw = profile.placement.rawValue
        model.ratingRaw = profile.rating.rawValue
        return model
    }
}

/// Waveform envelopes as a compact byte blob.
///
/// Stored as quantised bytes rather than `[Float]`: an envelope is only ever
/// drawn as a bar height, so 8 bits of precision is indistinguishable on screen
/// while being a quarter of the size. A night with 300 events saves roughly a
/// megabyte, every night, forever.
enum WaveformCoding {

    static func encode(_ samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count)
        for sample in samples {
            let clamped = min(max(sample.isFinite ? sample : 0, 0), 1)
            bytes.append(UInt8((clamped * 255).rounded()))
        }
        return Data(bytes)
    }

    static func decode(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else { return [] }
        return data.map { Float($0) / 255 }
    }
}
