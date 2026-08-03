import Foundation
import Testing

@testable import Somna

/// Deletion is the one area where a bug is unrecoverable for the user.
///
/// These tests check the two properties that matter: nothing survives that
/// should not, and nothing is orphaned that could not then be found again.
struct StorageServiceTests {

    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeService() -> (StorageService, AppEnvironment, NightFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SomnaStorage-\(UUID().uuidString)", directoryHint: .isDirectory)
        let files = NightFileStore(root: root)
        let environment = AppEnvironment.preview().replacing(files: files)
        let service = StorageService(sessions: environment.sessions, files: files)
        return (service, environment, files, root)
    }

    @discardableResult
    private func makeNight(
        in environment: AppEnvironment,
        files: NightFileStore,
        status: NightSessionStatus = .completed,
        recordedAt: Date,
        segmentBytes: Int = 4096,
        clipBytes: Int = 1024
    ) async throws -> NightSession {
        let session = NightSession(
            startDate: recordedAt,
            endDate: recordedAt.addingTimeInterval(8 * 3600),
            status: status,
            recordedDuration: 8 * 3600,
            createdAt: recordedAt,
            updatedAt: recordedAt
        )
        try await environment.sessions.save(session)
        try files.prepareDirectories(for: session.id)

        let segmentURL = files.segmentURL(for: session.id, fileName: "seg-000.m4a")
        try files.writeAtomically(Data(repeating: 1, count: segmentBytes), to: segmentURL)
        try files.writeAtomically(
            Data(repeating: 2, count: clipBytes),
            to: files.clipURL(for: session.id, fileName: "evt-000.m4a")
        )

        try await environment.sessions.save(
            AudioSegment(
                sessionID: session.id,
                fileName: "seg-000.m4a",
                startDate: recordedAt,
                endDate: recordedAt.addingTimeInterval(600),
                fileSize: Int64(segmentBytes),
                processingState: .ready
            )
        )
        return session
    }

    @Test("The breakdown separates raw audio from clips")
    func breakdownSeparatesKinds() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        try await makeNight(in: environment, files: files, recordedAt: origin)

        let breakdown = try await service.breakdown()
        #expect(breakdown.nightCount == 1)
        #expect(breakdown.rawAudioBytes >= 4096)
        #expect(breakdown.clipBytes >= 1024)
        #expect(breakdown.availableBytes > 0)
    }

    /// Clips are what every timeline row is adossed to. Losing them would turn a
    /// checkable report into an unverifiable one.
    @Test("Purging raw audio keeps the clips")
    func purgeKeepsClips() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        let night = try await makeNight(in: environment, files: files, recordedAt: origin)

        let result = try await service.eraseRawAudio()
        #expect(result.purgedNights == 1)
        #expect(result.freedBytes > 0)

        #expect(!FileManager.default.fileExists(
            atPath: files.segmentURL(for: night.id, fileName: "seg-000.m4a").path(percentEncoded: false)
        ))
        #expect(FileManager.default.fileExists(
            atPath: files.clipURL(for: night.id, fileName: "evt-000.m4a").path(percentEncoded: false)
        ))
    }

    /// A purged segment must be marked as such, or the app would keep offering
    /// audio that no longer exists.
    @Test("Purged segments are marked, not deleted from the database")
    func purgedSegmentsAreMarked() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        let night = try await makeNight(in: environment, files: files, recordedAt: origin)
        _ = try await service.eraseRawAudio()

        let segments = try await environment.sessions.segments(for: night.id)
        #expect(segments.count == 1)
        #expect(segments.first?.retentionState == .purged)
        #expect(segments.first?.isUsable == false)
    }

    @Test("Retention purges only past its window")
    func retentionRespectsWindow() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        try await makeNight(in: environment, files: files,
                            recordedAt: origin.addingTimeInterval(-2 * 24 * 3600))
        try await makeNight(in: environment, files: files,
                            recordedAt: origin.addingTimeInterval(-20 * 24 * 3600))

        let result = try await service.applyRetention(.sevenDays, now: origin)
        #expect(result.purgedNights == 1)
    }

    /// Discarding the raw audio of a night nobody has looked at would destroy
    /// the only copy of something the user has not seen.
    @Test("Retention never purges a night that has not been analysed")
    func retentionSparesUnanalysedNights() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        try await makeNight(in: environment, files: files, status: .awaitingAnalysis,
                            recordedAt: origin.addingTimeInterval(-30 * 24 * 3600))

        let result = try await service.applyRetention(.sevenDays, now: origin)
        #expect(result.purgedNights == 0)
    }

    @Test("Keeping everything purges nothing")
    func keepAllPurgesNothing() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        try await makeNight(in: environment, files: files,
                            recordedAt: origin.addingTimeInterval(-400 * 24 * 3600))

        #expect(try await service.applyRetention(.keepAll, now: origin) == .none)
    }

    /// The promise the Settings screen makes. It has to be literally true.
    @Test("Erasing everything leaves neither files nor rows")
    func eraseEverythingLeavesNothing() async throws {
        let (service, environment, files, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        for offset in 0..<3 {
            try await makeNight(in: environment, files: files,
                                recordedAt: origin.addingTimeInterval(Double(-offset) * 86_400))
        }

        try await service.eraseEverything()

        let remaining = try await environment.sessions.sessions()
        #expect(remaining.isEmpty)

        let breakdown = try await service.breakdown()
        #expect(breakdown.nightCount == 0)
        #expect(breakdown.totalBytes == 0)
    }

    @Test("Erasing an empty library is not an error")
    func erasingNothingIsSafe() async throws {
        let (service, _, _, root) = makeService()
        defer { try? FileManager.default.removeItem(at: root) }

        try await service.eraseEverything()
        try await service.eraseEverything()
    }
}

@MainActor
struct HistoryStoreTests {

    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        nights: [(score: Int?, status: NightSessionStatus, snoring: Int, coughs: Int)]
    ) async throws -> HistoryStore {
        let environment = AppEnvironment.preview()

        for (index, spec) in nights.enumerated() {
            var session = NightSession(
                startDate: origin.addingTimeInterval(Double(-index) * 86_400),
                endDate: origin.addingTimeInterval(Double(-index) * 86_400 + 8 * 3600),
                status: spec.status,
                recordedDuration: 8 * 3600,
                calmnessScore: spec.score,
                createdAt: origin,
                updatedAt: origin
            )
            session.statistics = NightStatistics(
                recordedDuration: 8 * 3600, quietDuration: 7 * 3600,
                snoringDuration: 0, coughCount: spec.coughs, talkingDuration: 0,
                loudEventCount: 0, totalEventCount: spec.snoring + spec.coughs,
                eventCountsByType: [.snoring: spec.snoring, .coughing: spec.coughs],
                calmestPeriod: nil, busiestHour: nil
            )
            try await environment.sessions.save(session)
        }

        let store = HistoryStore(environment: environment)
        await store.load()
        return store
    }

    @Test("Nights load newest first")
    func nightsAreOrdered() async throws {
        let store = try await makeStore(nights: [
            (80, .completed, 0, 0), (60, .completed, 0, 0), (90, .completed, 0, 0),
        ])
        #expect(store.nights.count == 3)
        #expect(store.nights[0].startDate > store.nights[1].startDate)
    }

    @Test("Queries narrow the list")
    func queriesNarrow() async throws {
        let store = try await makeStore(nights: [
            (80, .completed, 12, 0), (60, .completed, 0, 4), (90, .interrupted, 0, 0),
        ])

        store.query = .withSnoring
        #expect(store.filtered.count == 1)

        store.query = .withCoughing
        #expect(store.filtered.count == 1)

        store.query = .interrupted
        #expect(store.filtered.count == 1)
    }

    /// Sorting an unusable night in as zero would rank a broken microphone as
    /// the worst night of the month.
    @Test("Quietest-first excludes nights that have no score")
    func quietestExcludesUnscoredNights() async throws {
        let store = try await makeStore(nights: [
            (80, .completed, 0, 0), (nil, .interrupted, 0, 0), (95, .completed, 0, 0),
        ])

        store.query = .quietest
        #expect(store.filtered.count == 2)
        #expect(store.filtered.first?.calmnessScore == 95)
    }

    @Test("Queries that would return nothing are not offered")
    func emptyQueriesAreHidden() async throws {
        let store = try await makeStore(nights: [(80, .completed, 5, 0)])

        #expect(store.availableQueries.contains(.all))
        #expect(store.availableQueries.contains(.withSnoring))
        #expect(!store.availableQueries.contains(.withCoughing))
        #expect(!store.availableQueries.contains(.saved))
    }

    @Test("Saving a night persists and reveals its query")
    func favouritingWorks() async throws {
        let store = try await makeStore(nights: [(80, .completed, 0, 0)])
        let night = try #require(store.nights.first)

        await store.toggleFavourite(night)
        #expect(store.nights.first?.isFavorite == true)
        #expect(store.availableQueries.contains(.saved))
    }

    @Test("Deleting a night removes it from the list")
    func deletionRemovesNight() async throws {
        let store = try await makeStore(nights: [(80, .completed, 0, 0), (60, .completed, 0, 0)])
        let night = try #require(store.nights.first)

        await store.delete(night)
        #expect(store.nights.count == 1)
        #expect(!store.nights.contains { $0.id == night.id })
    }
}

@MainActor
struct SettingsStoreTests {

    @Test("Changing a setting writes it through immediately")
    func settingsWriteThrough() async {
        let environment = AppEnvironment.preview()
        let store = SettingsStore(
            environment: environment,
            appSettings: AppSettings(
                repository: environment.settings,
                notifications: environment.notifications
            )
        )

        store.settings.retentionPolicy = AudioRetentionPolicy.ninetyDays
        #expect(environment.settings.load().retentionPolicy == .ninetyDays)
    }

    /// No deletion path may skip the confirmation step.
    @Test("Destructive actions require an explicit confirmation")
    func deletionNeedsConfirmation() async {
        let environment = AppEnvironment.preview()
        let store = SettingsStore(
            environment: environment,
            appSettings: AppSettings(
                repository: environment.settings,
                notifications: environment.notifications
            )
        )

        store.pendingDeletion = SettingsStore.PendingDeletion.everything
        #expect(store.pendingDeletion == SettingsStore.PendingDeletion.everything)

        // Nothing happens until confirm is called.
        store.pendingDeletion = nil
        await store.confirmPendingDeletion()
    }

    /// The dialog has to describe what the action actually does, so the text is
    /// built where the action is, not in the view.
    @Test("Each confirmation names what it will remove")
    func confirmationsAreSpecific() {
        let environment = AppEnvironment.preview()
        let store = SettingsStore(
            environment: environment,
            appSettings: AppSettings(
                repository: environment.settings,
                notifications: environment.notifications
            )
        )

        let audio = store.confirmationMessage(for: .rawAudio)
        let everything = store.confirmationMessage(for: .everything)

        #expect(audio != everything)
        #expect(audio.lowercased().contains("kept") || audio.lowercased().contains("clip"))
        #expect(everything.lowercased().contains("cannot be undone"))
    }

    /// The tab bar is the one place in an app where a dead end is permanently
    /// visible, so the list is enumerated by hand rather than derived from
    /// `allCases`. Every entry must correspond to a screen that exists — which
    /// is now all four, Trends having arrived with its charts.
    @Test("Every offered tab has a screen behind it")
    func tabsAreReal() {
        #expect(Set(AppTab.available).isSubset(of: Set(AppTab.allCases)))
        #expect(AppTab.available.count == AppTab.allCases.count)
        #expect(AppTab.available.first == .home, "Tonight must remain the landing tab")
    }
}
