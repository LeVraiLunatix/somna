import Foundation
import Testing

@testable import Somna

@MainActor
struct TimelineStoreTests {

    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        with events: [(NightEventType, String?)]
    ) async throws -> (TimelineStore, NightSession) {
        let environment = AppEnvironment.preview()
        let session = NightSession(
            startDate: origin,
            endDate: origin.addingTimeInterval(8 * 3600),
            status: .completed,
            recordedDuration: 8 * 3600,
            createdAt: origin,
            updatedAt: origin
        )
        try await environment.sessions.save(session)

        let built = events.enumerated().map { index, spec in
            NightEvent(
                sessionID: session.id,
                type: spec.0,
                confidence: .high,
                startDate: origin.addingTimeInterval(Double(index) * 600),
                endDate: origin.addingTimeInterval(Double(index) * 600 + 20),
                clipFileName: spec.1,
                createdAt: origin
            )
        }
        try await environment.sessions.replaceEvents(built, for: session.id)

        let store = TimelineStore(environment: environment, sessionID: session.id)
        await store.load()
        return (store, session)
    }

    @Test("A night loads its events")
    func loadsEvents() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a"), (.coughing, "b.m4a")])
        #expect(store.state == .ready)
        #expect(store.allEvents.count == 2)
    }

    @Test("Filters narrow the list")
    func filtersNarrow() async throws {
        let (store, _) = try await makeStore(with: [
            (.snoring, "a.m4a"), (.snoring, "b.m4a"), (.coughing, "c.m4a"), (.rain, "d.m4a"),
        ])

        store.filter = .snoring
        #expect(store.events.count == 2)

        store.filter = .environment
        #expect(store.events.count == 1)

        store.filter = .all
        #expect(store.events.count == 4)
    }

    /// A chip that yields an empty list implies Somna looked for coughs and
    /// found none, when it may never have looked.
    @Test("Filters that would return nothing are not offered")
    func emptyFiltersAreHidden() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a")])

        #expect(store.availableFilters.contains(.all))
        #expect(store.availableFilters.contains(.snoring))
        #expect(!store.availableFilters.contains(.coughing))
        #expect(!store.availableFilters.contains(.favourites))
    }

    @Test("The playable queue skips events whose audio is gone")
    func queueSkipsMissingClips() async throws {
        let (store, _) = try await makeStore(with: [
            (.snoring, "a.m4a"), (.coughing, nil), (.rain, "c.m4a"),
        ])

        #expect(store.allEvents.count == 3)
        #expect(store.playableQueue.count == 2)
        #expect(store.playbackItems().count == 2)
    }

    @Test("The queue follows the active filter")
    func queueFollowsFilter() async throws {
        let (store, _) = try await makeStore(with: [
            (.snoring, "a.m4a"), (.coughing, "b.m4a"),
        ])

        store.filter = .coughing
        #expect(store.playableQueue.count == 1)
        #expect(store.playableQueue.first?.effectiveType == .coughing)
    }

    @Test("Saving a moment persists and toggles")
    func favouriteRoundTrips() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a")])
        let event = try #require(store.allEvents.first)

        await store.toggleFavourite(event)
        #expect(store.allEvents.first?.isFavorite == true)
        #expect(store.availableFilters.contains(.favourites))

        await store.toggleFavourite(try #require(store.allEvents.first))
        #expect(store.allEvents.first?.isFavorite == false)
    }

    /// The model's original guess must survive: the pair is the training signal
    /// a future model would need.
    @Test("A correction is recorded without erasing the model's guess")
    func correctionKeepsOriginal() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a")])
        let event = try #require(store.allEvents.first)

        await store.correct(event, to: .coughing)

        let updated = try #require(store.allEvents.first)
        #expect(updated.type == .snoring)
        #expect(updated.userCorrectedType == .coughing)
        #expect(updated.effectiveType == .coughing)
        #expect(updated.title == "Cough detected")
    }

    @Test("Correcting back to the original clears the correction")
    func correctionCanBeUndone() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a")])

        await store.correct(try #require(store.allEvents.first), to: .coughing)
        await store.correct(try #require(store.allEvents.first), to: .snoring)

        #expect(store.allEvents.first?.userCorrectedType == nil)
    }

    @Test("A correction re-files the event under its new filter")
    func correctionMovesBetweenFilters() async throws {
        let (store, _) = try await makeStore(with: [(.snoring, "a.m4a")])
        await store.correct(try #require(store.allEvents.first), to: .coughing)

        store.filter = .coughing
        #expect(store.events.count == 1)

        store.filter = .snoring
        #expect(store.events.isEmpty)
    }
}

@MainActor
struct ClipPlayerTests {

    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ index: Int) -> PlaybackItem {
        PlaybackItem(
            event: NightEvent(
                sessionID: UUID(),
                type: .snoring,
                confidence: .high,
                startDate: origin.addingTimeInterval(Double(index) * 600),
                endDate: origin.addingTimeInterval(Double(index) * 600 + 10),
                clipFileName: "evt-\(index).m4a",
                createdAt: origin
            ),
            url: FileManager.default.temporaryDirectory.appending(path: "missing-\(index).m4a")
        )
    }

    /// The clip may have been purged by the retention policy. The user tapped
    /// play and deserves to know why nothing happened.
    @Test("A missing clip reports an error rather than failing silently")
    func missingClipIsReported() {
        let player = ClipPlayer()
        let target = item(0)

        player.play(target, in: [target])

        #expect(player.failure == .corruptedFile)
        #expect(!player.isPlaying)
        #expect(player.current?.id == target.id)
    }

    @Test("Queue navigation knows where it is")
    func queueBounds() {
        let player = ClipPlayer()
        let items = (0..<3).map(item)

        player.play(items[0], in: items)
        #expect(player.canPlayNext)
        #expect(!player.canPlayPrevious)

        player.play(items[2], in: items)
        #expect(!player.canPlayNext)
        #expect(player.canPlayPrevious)
    }

    @Test("Dismissing clears the player")
    func dismissClears() {
        let player = ClipPlayer()
        let target = item(0)

        player.play(target, in: [target])
        player.dismiss()

        #expect(player.current == nil)
        #expect(player.failure == nil)
        #expect(!player.isPlaying)
    }

    @Test("Progress stays in range when nothing is loaded")
    func progressIsSafe() {
        #expect(ClipPlayer().progress == 0)
    }

    /// Slowing down is what makes a faint sound identifiable — the only reason
    /// rates exist here.
    @Test("Playback rates are offered below and at normal speed")
    func ratesAreForListeningCloser() {
        #expect(ClipPlayer.availableRates.allSatisfy { $0 <= 1 })
        #expect(ClipPlayer.availableRates.contains(1))
    }
}
