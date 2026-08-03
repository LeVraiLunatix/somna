import OSLog
import SwiftUI

/// Backs the history list.
@MainActor
@Observable
final class HistoryStore {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(SomnaError)
    }

    /// Search over nights, not over free text.
    ///
    /// Phase 1 chose a structured search over a chatbot that would pretend to
    /// understand. These are the questions people actually arrive with, and each
    /// one is answerable from stored data rather than guessed at.
    enum Query: String, CaseIterable, Identifiable, Sendable {
        case all
        case withSnoring
        case withCoughing
        case quietest
        case interrupted
        case saved

        var id: String { rawValue }
    }

    private(set) var state: LoadState = .loading
    private(set) var nights: [NightSession] = []
    private(set) var eventCounts: [UUID: [NightEventType: Int]] = [:]
    var query: Query = .all

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var filtered: [NightSession] {
        switch query {
        case .all:
            nights
        case .withSnoring:
            nights.filter { (eventCounts[$0.id]?[.snoring] ?? 0) > 0 }
        case .withCoughing:
            nights.filter { (eventCounts[$0.id]?[.coughing] ?? 0) > 0 }
        case .quietest:
            // Only nights that actually have a score: an unusable recording has
            // none, and sorting it in as zero would rank a broken microphone as
            // the worst night of the month.
            nights.filter { $0.calmnessScore != nil }
                .sorted { ($0.calmnessScore ?? 0) > ($1.calmnessScore ?? 0) }
        case .interrupted:
            nights.filter { $0.status == .interrupted }
        case .saved:
            nights.filter(\.isFavorite)
        }
    }

    /// Queries that would return nothing are not offered — same rule as the
    /// timeline's filters, for the same reason.
    var availableQueries: [Query] {
        Query.allCases.filter { candidate in
            candidate == .all || !nights(for: candidate).isEmpty
        }
    }

    private func nights(for query: Query) -> [NightSession] {
        let previous = self.query
        defer { self.query = previous }
        self.query = query
        return filtered
    }

    func load() async {
        state = .loading
        do {
            nights = try await environment.sessions.sessions()

            var counts: [UUID: [NightEventType: Int]] = [:]
            for night in nights {
                counts[night.id] = night.statistics?.eventCountsByType ?? [:]
            }
            eventCounts = counts
            state = .ready
        } catch let error as SomnaError {
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    func delete(_ session: NightSession) async {
        do {
            // Files first, then the row — the same order the storage service
            // uses, and for the same reason: the reverse leaves audio that
            // nothing references.
            try environment.files.removeSessionDirectory(for: session.id)
            try await environment.sessions.deleteSession(id: session.id)
            nights.removeAll { $0.id == session.id }
            environment.haptics.play(.deletionConfirmed)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: "delete"))
        }
    }

    func toggleFavourite(_ session: NightSession) async {
        var updated = session
        updated.isFavorite.toggle()
        updated.updatedAt = environment.clock.now

        do {
            try await environment.sessions.save(updated)
            if let index = nights.firstIndex(where: { $0.id == session.id }) {
                nights[index] = updated
            }
        } catch {
            // The list is left untouched rather than showing a bookmark that
            // will be gone after a reload. Silently accepting the failure would
            // read as "the app forgot", which is worse than an honest refusal.
            Log.ui.error("Night favourite could not be saved")
            state = .failed(.persistenceUnavailable(underlying: "favourite"))
        }
    }
}

/// Every night Somna has recorded.
struct HistoryView: View {

    @Environment(\.somnaPalette) private var palette

    @Environment(\.somna) private var environment
    @State private var store: HistoryStore?

    let onOpenNight: (UUID) -> Void
    let onStartSession: () -> Void

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("history.root")
        .navigationTitle(Text(String(localized: "history.title", defaultValue: "Nights")))
        .task {
            if store == nil { store = HistoryStore(environment: environment) }
            await store?.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(message: String(localized: "history.loading", defaultValue: "Loading…"))
        case .failed(let error):
            ErrorStateView(error: error) { Task { await store?.load() } }
        case .ready:
            if let store {
                if store.nights.isEmpty {
                    EmptyStateView(
                        symbolName: "moon.stars",
                        title: String(localized: "history.empty.title",
                                      defaultValue: "No nights yet"),
                        message: String(localized: "history.empty.body",
                                        defaultValue: "Once you record a night it will appear here, with everything Somna heard."),
                        actionTitle: String(localized: "history.empty.action",
                                            defaultValue: "Record tonight"),
                        action: onStartSession
                    )
                } else {
                    list(store)
                }
            }
        }
    }

    private func list(_ store: HistoryStore) -> some View {
        @Bindable var store = store

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: SomnaSpacing.m) {
                if store.availableQueries.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: SomnaSpacing.s) {
                            ForEach(store.availableQueries) { query in
                                Button {
                                    store.query = query
                                } label: {
                                    Text(title(for: query)).font(SomnaFont.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(store.query == query
                                      ? palette.accentPrimary : SomnaColor.textTertiary)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                ForEach(store.filtered) { night in
                    Button {
                        onOpenNight(night.id)
                    } label: {
                        HistoryRow(night: night)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { await store.toggleFavourite(night) }
                        } label: {
                            Label(
                                night.isFavorite
                                    ? String(localized: "history.unsave", defaultValue: "Remove from saved")
                                    : String(localized: "history.save", defaultValue: "Save this night"),
                                systemImage: night.isFavorite ? "bookmark.slash" : "bookmark"
                            )
                        }

                        Button(role: .destructive) {
                            Task { await store.delete(night) }
                        } label: {
                            Label(
                                String(localized: "history.delete", defaultValue: "Delete this night"),
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .padding(SomnaSpacing.l)
        }
    }

    private func title(for query: HistoryStore.Query) -> String {
        switch query {
        case .all: String(localized: "history.query.all", defaultValue: "All")
        case .withSnoring: String(localized: "history.query.snoring", defaultValue: "With snoring")
        case .withCoughing: String(localized: "history.query.coughing", defaultValue: "With coughing")
        case .quietest: String(localized: "history.query.quietest", defaultValue: "Quietest first")
        case .interrupted: String(localized: "history.query.interrupted", defaultValue: "Interrupted")
        case .saved: String(localized: "history.query.saved", defaultValue: "Saved")
        }
    }
}

/// One night in the list.
struct HistoryRow: View {

    @Environment(\.somnaPalette) private var palette

    let night: NightSession

    private func statistics(_ night: NightSession, layout: AnyLayout) -> some View {
        layout {
            Label(
                night.recordedDuration.formattedCompactDuration,
                systemImage: "waveform"
            )

            if let stats = night.statistics {
                if let snoring = stats.eventCountsByType[.snoring], snoring > 0 {
                    Label("\(snoring)", systemImage: "zzz")
                }
                if stats.coughCount > 0 {
                    Label("\(stats.coughCount)", systemImage: "lungs")
                }
            }
        }
    }

    var body: some View {
        SomnaCard {
            HStack(alignment: .firstTextBaseline) {
                Text(night.startDate.formatted(date: .abbreviated, time: .omitted))
                    .fixedSize(horizontal: false, vertical: true)
                    .font(SomnaFont.cardTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                if night.isFavorite {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accentSecondary)
                        .accessibilityLabel(Text(String(localized: "history.saved",
                                                        defaultValue: "Saved")))
                }

                Spacer()

                if let score = night.calmnessScore {
                    Text("\(score)")
                        .font(SomnaFont.statValue)
                        .foregroundStyle(SomnaColor.textPrimary)
                }
            }

            // A row of fixed columns clips at the larger text sizes.
            // `ViewThatFits` keeps one line while it fits and wraps to a column
            // when it does not, rather than truncating figures the user came
            // to read.
            ViewThatFits(in: .horizontal) {
                statistics(night, layout: AnyLayout(HStackLayout(spacing: SomnaSpacing.m)))
                statistics(night, layout: AnyLayout(VStackLayout(alignment: .leading,
                                                                spacing: SomnaSpacing.xs)))
            }
            .font(SomnaFont.caption)
            .foregroundStyle(SomnaColor.textSecondary)

            // Interrupted nights say so in the list, not only inside the report:
            // otherwise a night with half the audio sits next to a complete one
            // looking identical.
            if night.status == .interrupted {
                Label(
                    String(localized: "history.interrupted", defaultValue: "Stopped early"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
