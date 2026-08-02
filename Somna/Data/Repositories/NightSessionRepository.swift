import Foundation
import SwiftData
import OSLog

/// SwiftData-backed implementation of ``NightSessionRepositing``.
///
/// A `@ModelActor`, so every fetch and write happens off the main thread. The
/// history screen loads dozens of nights and the analysis pipeline writes
/// hundreds of events; doing either on the main actor would drop frames during
/// exactly the moments the app is meant to feel calm.
///
/// Only domain values cross the actor boundary — never a `PersistentModel`,
/// which is not `Sendable` and is bound to the context that fetched it.
@ModelActor
actor NightSessionRepository: NightSessionRepositing {

    // MARK: - Sessions

    func sessions(limit: Int?, offset: Int) async throws -> [NightSession] {
        var descriptor = FetchDescriptor<SDNightSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchOffset = max(0, offset)
        if let limit { descriptor.fetchLimit = max(0, limit) }

        return try modelContext.fetch(descriptor).map(NightSessionMapper.toDomain)
    }

    func session(id: UUID) async throws -> NightSession? {
        try fetchModel(id: id).map(NightSessionMapper.toDomain)
    }

    func mostRecentSession() async throws -> NightSession? {
        var descriptor = FetchDescriptor<SDNightSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(NightSessionMapper.toDomain)
    }

    func unfinishedSessions() async throws -> [NightSession] {
        let running = NightSessionStatus.recording.rawValue
        let interrupted = NightSessionStatus.interrupted.rawValue
        let descriptor = FetchDescriptor<SDNightSession>(
            predicate: #Predicate { $0.statusRaw == running || $0.statusRaw == interrupted },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(NightSessionMapper.toDomain)
    }

    /// Upsert: creates the row on first save, updates it afterwards.
    ///
    /// A single entry point avoids the classic bug where a caller inserts twice
    /// because it could not tell whether the night already existed.
    func save(_ session: NightSession) async throws {
        if let existing = try fetchModel(id: session.id) {
            NightSessionMapper.apply(session, to: existing)
        } else {
            modelContext.insert(NightSessionMapper.makeModel(from: session))
        }
        try commit()
    }

    func deleteSession(id: UUID) async throws {
        guard let model = try fetchModel(id: id) else {
            throw SomnaError.sessionNotFound(id: id)
        }
        // Events and segments cascade; the audio files themselves are removed by
        // `DeleteNightUseCase`, which deletes on disk *before* calling this so a
        // failure here can never leave unreferenced files behind.
        modelContext.delete(model)
        try commit()
    }

    func deleteAllSessions() async throws {
        try modelContext.delete(model: SDNightSession.self)
        try modelContext.delete(model: SDNightEvent.self)
        try modelContext.delete(model: SDAudioSegment.self)
        try commit()
    }

    // MARK: - Events

    func events(for sessionID: UUID) async throws -> [NightEvent] {
        guard let session = try fetchModel(id: sessionID) else { return [] }
        return (session.events ?? [])
            .sorted { $0.startDate < $1.startDate }
            .map { NightEventMapper.toDomain($0, sessionID: sessionID) }
    }

    func replaceEvents(_ events: [NightEvent], for sessionID: UUID) async throws {
        guard let session = try fetchModel(id: sessionID) else {
            throw SomnaError.sessionNotFound(id: sessionID)
        }

        for existing in session.events ?? [] {
            modelContext.delete(existing)
        }

        for event in events {
            let model = NightEventMapper.makeModel(from: event)
            model.session = session
            modelContext.insert(model)
        }

        try commit()
    }

    func updateEvent(_ event: NightEvent) async throws {
        let id = event.id
        var descriptor = FetchDescriptor<SDNightEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        guard let model = try modelContext.fetch(descriptor).first else { return }
        NightEventMapper.apply(event, to: model)
        try commit()
    }

    // MARK: - Segments

    func segments(for sessionID: UUID) async throws -> [AudioSegment] {
        guard let session = try fetchModel(id: sessionID) else { return [] }
        return (session.segments ?? [])
            .sorted { $0.startDate < $1.startDate }
            .map { AudioSegmentMapper.toDomain($0, sessionID: sessionID) }
    }

    func save(_ segment: AudioSegment) async throws {
        let id = segment.id
        var descriptor = FetchDescriptor<SDAudioSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            AudioSegmentMapper.apply(segment, to: existing)
        } else {
            guard let session = try fetchModel(id: segment.sessionID) else {
                throw SomnaError.sessionNotFound(id: segment.sessionID)
            }
            let model = AudioSegmentMapper.makeModel(from: segment)
            model.session = session
            modelContext.insert(model)
        }
        try commit()
    }

    // MARK: - Calibration

    func latestCalibration() async throws -> CalibrationProfile? {
        var descriptor = FetchDescriptor<SDCalibrationProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(CalibrationMapper.toDomain)
    }

    func save(_ calibration: CalibrationProfile) async throws {
        modelContext.insert(CalibrationMapper.makeModel(from: calibration))
        try commit()
    }

    // MARK: - Helpers

    private func fetchModel(id: UUID) throws -> SDNightSession? {
        var descriptor = FetchDescriptor<SDNightSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Saves, translating any store failure into a domain error.
    ///
    /// Deliberately not `try?`: a swallowed save is a night that looks recorded
    /// in the UI and is absent on next launch.
    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            Log.persistence.error("Save failed: \(String(describing: type(of: error)), privacy: .public)")
            throw SomnaError.persistenceUnavailable(underlying: String(describing: type(of: error)))
        }
    }
}
