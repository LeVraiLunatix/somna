import Foundation
import OSLog

/// Backs the timeline and the report's event list.
@MainActor
@Observable
final class TimelineStore {

    /// The filters offered above the list.
    ///
    /// Deliberately few. A filter per event type would give sixteen chips for a
    /// night that usually contains three kinds of sound; these are the questions
    /// people actually arrive with.
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all
        case snoring
        case coughing
        case speech
        case environment
        case favourites

        var id: String { rawValue }

        func matches(_ event: NightEvent) -> Bool {
            switch self {
            case .all: true
            case .snoring: event.effectiveType == .snoring
            case .coughing: event.effectiveType == .coughing
            case .speech: event.effectiveType == .talking
            case .environment: event.effectiveType.category == .environment
            case .favourites: event.isFavorite
            }
        }
    }

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(SomnaError)
    }

    private(set) var state: LoadState = .loading
    private(set) var session: NightSession?
    private(set) var allEvents: [NightEvent] = []
    var filter: Filter = .all

    private let environment: AppEnvironment
    private let sessionID: UUID

    init(environment: AppEnvironment, sessionID: UUID) {
        self.environment = environment
        self.sessionID = sessionID
    }

    var events: [NightEvent] {
        allEvents.filter(filter.matches)
    }

    /// Filters that would return nothing are not offered.
    ///
    /// A chip that yields an empty list is a small betrayal: it implies the app
    /// looked for coughs and found none, when it may never have looked.
    var availableFilters: [Filter] {
        Filter.allCases.filter { candidate in
            candidate == .all || allEvents.contains(where: candidate.matches)
        }
    }

    /// Events that have audio, in timeline order — the queue the player walks.
    var playableQueue: [NightEvent] {
        events.filter(\.hasPlayableClip)
    }

    func load() async {
        state = .loading
        do {
            session = try await environment.sessions.session(id: sessionID)
            allEvents = try await environment.sessions.events(for: sessionID)
            state = .ready
        } catch let error as SomnaError {
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    func url(for event: NightEvent) -> URL? {
        guard let fileName = event.clipFileName else { return nil }
        return environment.files.clipURL(for: sessionID, fileName: fileName)
    }

    func playbackItems() -> [PlaybackItem] {
        playableQueue.compactMap { event in
            url(for: event).map { PlaybackItem(event: event, url: $0) }
        }
    }

    // MARK: - Editing

    func toggleFavourite(_ event: NightEvent) async {
        var updated = event
        updated.isFavorite.toggle()
        await persist(updated)
        environment.haptics.play(.eventSelected)
    }

    /// Records what the user says an event actually was.
    ///
    /// The model's original guess is kept alongside — see `NightEvent` — so the
    /// pair remains available as training signal. Correcting also re-runs nothing:
    /// the report's statistics are recomputed on next analysis, not silently
    /// rewritten under the user, which would make the numbers move without
    /// explanation.
    func correct(_ event: NightEvent, to type: NightEventType) async {
        var updated = event
        updated.userCorrectedType = type == event.type ? nil : type
        await persist(updated)
        environment.haptics.play(.eventSelected)
    }

    private func persist(_ event: NightEvent) async {
        do {
            try await environment.sessions.updateEvent(event)
            if let index = allEvents.firstIndex(where: { $0.id == event.id }) {
                allEvents[index] = event
            }
        } catch {
            Log.ui.error("Event update could not be saved")
        }
    }
}
