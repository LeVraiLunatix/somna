import Foundation
import SwiftData
import Testing

@testable import Somna

/// Exercises the real SwiftData stack against an in-memory store.
///
/// These are the tests that would catch the Phase 1 risk R5 turning real: a
/// schema that will not open, a relationship that does not cascade, a mapper
/// that drops a field. They run against the actual container the app builds,
/// not a stub, because a stub cannot fail the way SwiftData fails.
struct PersistenceTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRepository() throws -> NightSessionRepository {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        return NightSessionRepository(modelContainer: container)
    }

    private func makeSession(id: UUID = UUID()) -> NightSession {
        NightSession(
            id: id,
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            status: .completed,
            recordedDuration: 7.5 * 3600,
            calmnessScore: 82,
            summaryStatements: [.overallCalm, .coughs(count: 3)],
            recordingQuality: RecordingQuality(
                rating: .good,
                issues: [.sessionInterrupted],
                averageNoiseFloor: 0.12,
                coverage: 0.94
            ),
            createdAt: start,
            updatedAt: start
        )
    }

    @Test("A session survives a full write and read cycle")
    func sessionRoundTrip() async throws {
        let repository = try makeRepository()
        let session = makeSession()

        try await repository.save(session)
        let loaded = try #require(await repository.session(id: session.id))

        #expect(loaded.id == session.id)
        #expect(loaded.status == .completed)
        #expect(loaded.calmnessScore == 82)
        #expect(loaded.summaryStatements == [.overallCalm, .coughs(count: 3)])
        #expect(loaded.recordingQuality?.rating == .good)
        #expect(loaded.recordingQuality?.issues == [.sessionInterrupted])
        #expect(abs((loaded.recordingQuality?.coverage ?? 0) - 0.94) < 0.0001)
    }

    /// One entry point for insert and update. Without this, a caller that cannot
    /// tell whether a night exists creates a duplicate.
    @Test("Saving twice updates rather than duplicating")
    func saveIsAnUpsert() async throws {
        let repository = try makeRepository()
        var session = makeSession()

        try await repository.save(session)
        session.calmnessScore = 41
        session.summaryStatements = [.overallActive(eventCount: 90)]
        try await repository.save(session)

        let all = try await repository.sessions()
        #expect(all.count == 1)
        #expect(all.first?.calmnessScore == 41)
    }

    @Test("Sessions come back newest first")
    func sessionsAreSortedNewestFirst() async throws {
        let repository = try makeRepository()

        for offset in 0..<3 {
            var session = makeSession()
            session.startDate = start.addingTimeInterval(TimeInterval(offset) * 86_400)
            try await repository.save(session)
        }

        let sessions = try await repository.sessions()
        #expect(sessions.count == 3)
        #expect(sessions[0].startDate > sessions[1].startDate)
        #expect(sessions[1].startDate > sessions[2].startDate)
    }

    @Test("Pagination limits and offsets correctly")
    func pagination() async throws {
        let repository = try makeRepository()
        for offset in 0..<5 {
            var session = makeSession()
            session.startDate = start.addingTimeInterval(TimeInterval(offset) * 86_400)
            try await repository.save(session)
        }

        let firstPage = try await repository.sessions(limit: 2, offset: 0)
        let secondPage = try await repository.sessions(limit: 2, offset: 2)

        #expect(firstPage.count == 2)
        #expect(secondPage.count == 2)
        #expect(firstPage.first?.id != secondPage.first?.id)
    }

    @Test("Events round-trip with their waveform and grouping intact")
    func eventRoundTrip() async throws {
        let repository = try makeRepository()
        let session = makeSession()
        try await repository.save(session)

        let event = NightEvent(
            sessionID: session.id,
            type: .snoring,
            confidence: .high,
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(3660),
            occurrenceCount: 12,
            peakLevel: 0.8,
            averageLevel: 0.4,
            waveformSamples: [0, 0.5, 1, 0.5],
            clipFileName: "evt-1.m4a",
            createdAt: start
        )
        try await repository.replaceEvents([event], for: session.id)

        let loaded = try #require(await repository.events(for: session.id).first)
        #expect(loaded.type == .snoring)
        #expect(loaded.occurrenceCount == 12)
        #expect(loaded.isGrouped)
        #expect(loaded.clipFileName == "evt-1.m4a")
        #expect(loaded.waveformSamples.count == 4)
    }

    @Test("Replacing events removes the previous set")
    func replaceEventsIsDestructive() async throws {
        let repository = try makeRepository()
        let session = makeSession()
        try await repository.save(session)

        func event(_ type: NightEventType) -> NightEvent {
            NightEvent(
                sessionID: session.id,
                type: type,
                confidence: .medium,
                startDate: start,
                endDate: start.addingTimeInterval(10),
                createdAt: start
            )
        }

        try await repository.replaceEvents([event(.snoring), event(.coughing)], for: session.id)
        let afterFirstWrite = try await repository.events(for: session.id)
        #expect(afterFirstWrite.count == 2)

        try await repository.replaceEvents([event(.rain)], for: session.id)
        let remaining = try await repository.events(for: session.id)
        #expect(remaining.count == 1)
        #expect(remaining.first?.type == .rain)
    }

    @Test("A user correction persists without losing the model's guess")
    func correctionPersists() async throws {
        let repository = try makeRepository()
        let session = makeSession()
        try await repository.save(session)

        var event = NightEvent(
            sessionID: session.id,
            type: .snoring,
            confidence: .medium,
            startDate: start,
            endDate: start.addingTimeInterval(20),
            createdAt: start
        )
        try await repository.replaceEvents([event], for: session.id)

        event.userCorrectedType = .breathing
        try await repository.updateEvent(event)

        let loaded = try #require(await repository.events(for: session.id).first)
        #expect(loaded.type == .snoring)
        #expect(loaded.userCorrectedType == .breathing)
        #expect(loaded.effectiveType == .breathing)
    }

    /// Orphaned events would keep occupying space while being unreachable from
    /// any screen — invisible storage growth, the hardest kind to diagnose.
    @Test("Deleting a session cascades to its events and segments")
    func deleteCascades() async throws {
        let repository = try makeRepository()
        let session = makeSession()
        try await repository.save(session)

        try await repository.replaceEvents(
            [NightEvent(
                sessionID: session.id,
                type: .coughing,
                confidence: .high,
                startDate: start,
                endDate: start.addingTimeInterval(2),
                createdAt: start
            )],
            for: session.id
        )
        try await repository.save(
            AudioSegment(
                sessionID: session.id,
                fileName: "seg-000.m4a",
                startDate: start,
                endDate: start.addingTimeInterval(600)
            )
        )

        let storedSegments = try await repository.segments(for: session.id)
        #expect(storedSegments.count == 1)

        try await repository.deleteSession(id: session.id)

        let deletedSession = try await repository.session(id: session.id)
        let orphanEvents = try await repository.events(for: session.id)
        let orphanSegments = try await repository.segments(for: session.id)
        #expect(deletedSession == nil)
        #expect(orphanEvents.isEmpty)
        #expect(orphanSegments.isEmpty)
    }

    @Test("Deleting an unknown session reports it instead of failing silently")
    func deletingUnknownSessionThrows() async throws {
        let repository = try makeRepository()
        let id = UUID()

        await #expect(throws: SomnaError.sessionNotFound(id: id)) {
            try await repository.deleteSession(id: id)
        }
    }

    @Test("Erasing everything leaves nothing behind")
    func deleteAll() async throws {
        let repository = try makeRepository()
        for _ in 0..<3 {
            let session = makeSession()
            try await repository.save(session)
            try await repository.replaceEvents(
                [NightEvent(
                    sessionID: session.id,
                    type: .rain,
                    confidence: .high,
                    startDate: start,
                    endDate: start,
                    createdAt: start
                )],
                for: session.id
            )
        }

        try await repository.deleteAllSessions()
        let remaining = try await repository.sessions()
        #expect(remaining.isEmpty)
    }

    @Test("Unfinished sessions are recoverable after an interruption")
    func unfinishedSessionsAreFound() async throws {
        let repository = try makeRepository()

        var interrupted = makeSession()
        interrupted.status = .interrupted
        try await repository.save(interrupted)
        try await repository.save(makeSession())

        let unfinished = try await repository.unfinishedSessions()
        #expect(unfinished.count == 1)
        #expect(unfinished.first?.id == interrupted.id)
    }

    @Test("Segments round-trip and report usability")
    func segmentRoundTrip() async throws {
        let repository = try makeRepository()
        let session = makeSession()
        try await repository.save(session)

        var segment = AudioSegment(
            sessionID: session.id,
            fileName: "seg-000.m4a",
            startDate: start,
            endDate: start.addingTimeInterval(600),
            fileSize: 2_400_000,
            processingState: .ready
        )
        try await repository.save(segment)

        var loaded = try #require(await repository.segments(for: session.id).first)
        #expect(loaded.fileSize == 2_400_000)
        #expect(loaded.isUsable)

        segment.retentionState = .purged
        try await repository.save(segment)

        loaded = try #require(await repository.segments(for: session.id).first)
        #expect(!loaded.isUsable)
        let afterPurge = try await repository.segments(for: session.id)
        #expect(afterPurge.count == 1, "Purging retention state must not create a second row")
    }

    @Test("The most recent calibration wins")
    func latestCalibration() async throws {
        let repository = try makeRepository()

        try await repository.save(
            CalibrationProfile(ambientNoiseFloor: 0.30, rating: .needsImprovement, createdAt: start)
        )
        try await repository.save(
            CalibrationProfile(
                ambientNoiseFloor: 0.05,
                rating: .excellent,
                createdAt: start.addingTimeInterval(86_400)
            )
        )

        let latest = try #require(await repository.latestCalibration())
        #expect(latest.rating == .excellent)
    }
}

struct SettingsRepositoryTests {

    @Test("Settings survive a round trip")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "somna.tests.\(UUID().uuidString)"))
        let repository = SettingsRepository(defaults: defaults)

        var settings = UserSettings.default
        settings.retentionPolicy = .ninetyDays
        settings.theme = .dark
        settings.hasCompletedOnboarding = true
        repository.save(settings)

        let loaded = repository.load()
        #expect(loaded.retentionPolicy == .ninetyDays)
        #expect(loaded.theme == .dark)
        #expect(loaded.hasCompletedOnboarding)
    }

    @Test("An empty store yields defaults")
    func emptyStoreYieldsDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "somna.tests.\(UUID().uuidString)"))
        #expect(SettingsRepository(defaults: defaults).load() == .default)
    }

    /// Settings are preferences, never data. Corrupt preferences must degrade to
    /// defaults, not block launch.
    @Test("Corrupt settings fall back to defaults instead of throwing")
    func corruptDataFallsBack() throws {
        let suite = "somna.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "somna.settings.v1")

        #expect(SettingsRepository(defaults: defaults).load() == .default)
    }
}
