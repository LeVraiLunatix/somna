import SwiftUI

/// Backs the night report.
@MainActor
@Observable
final class NightReportStore {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(SomnaError)
    }

    private(set) var state: LoadState = .loading
    private(set) var session: NightSession?
    private(set) var events: [NightEvent] = []
    private(set) var isReanalysing = false

    private let environment: AppEnvironment
    private let sessionID: UUID

    init(environment: AppEnvironment, sessionID: UUID) {
        self.environment = environment
        self.sessionID = sessionID
    }

    /// The handful of moments worth listening to first.
    ///
    /// Loudest and most confident, capped at five. A "key moments" list of
    /// thirty is a second timeline, not a shortcut.
    var keyMoments: [NightEvent] {
        events
            .filter { $0.hasPlayableClip && $0.effectiveType != .sessionGap }
            .sorted { ($0.peakLevel, $0.occurrenceCount) > ($1.peakLevel, $1.occurrenceCount) }
            .prefix(5)
            .sorted { $0.startDate < $1.startDate }
    }

    /// Whether the report should hold back its numbers.
    var suppressesStatistics: Bool {
        session?.recordingQuality?.suppressesConclusions ?? false
    }

    func load() async {
        state = .loading
        do {
            session = try await environment.sessions.session(id: sessionID)
            events = try await environment.sessions.events(for: sessionID)
            state = session == nil ? .failed(.sessionNotFound(id: sessionID)) : .ready
        } catch let error as SomnaError {
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    /// Re-runs the morning pass, for a night whose analysis failed or which was
    /// analysed by an older version of the pipeline.
    func reanalyse() async {
        guard !isReanalysing else { return }
        isReanalysing = true
        defer { isReanalysing = false }

        let useCase = AnalyzeNightUseCase(
            sessions: environment.sessions,
            analyser: environment.analyser,
            settings: environment.settings,
            clock: environment.clock
        )
        _ = try? await useCase(sessionID: sessionID)
        await load()
    }

    func playbackItems() -> [PlaybackItem] {
        events.compactMap { event in
            guard let name = event.clipFileName else { return nil }
            return PlaybackItem(
                event: event,
                url: environment.files.clipURL(for: sessionID, fileName: name)
            )
        }
    }
}

/// What happened last night.
struct NightReportView: View {

    @Environment(\.somna) private var environment
    @Environment(ClipPlayer.self) private var player
    @State private var store: NightReportStore?

    let sessionID: UUID
    let onShowTimeline: () -> Void

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("report.root")
        .navigationTitle(Text(String(localized: "report.title", defaultValue: "Your night")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = NightReportStore(environment: environment, sessionID: sessionID)
            }
            await store?.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(message: String(localized: "report.loading",
                                             defaultValue: "Opening your night…"))
        case .failed(let error):
            ErrorStateView(error: error) { Task { await store?.load() } }
        case .ready:
            if let store, let session = store.session {
                ScrollView {
                    VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                        header(session)
                        quality(session, store: store)
                        summary(session)

                        // Numbers drawn from unusable audio are worse than no
                        // numbers: they look like findings.
                        if !store.suppressesStatistics {
                            score(session)
                            statistics(session)
                            keyMoments(store)
                        }

                        timelineLink(store)
                    }
                    .padding(SomnaSpacing.l)
                    .padding(.bottom, player.current == nil ? 0 : 96)
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ session: NightSession) -> some View {
        VStack(alignment: .leading, spacing: SomnaSpacing.xs) {
            Text(session.startDate.formatted(date: .complete, time: .omitted))
                .font(SomnaFont.screenTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            Text(range(session))
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)
        }
    }

    private func range(_ session: NightSession) -> String {
        let start = session.startDate.formatted(.dateTime.hour().minute())
        guard let end = session.endDate?.formatted(.dateTime.hour().minute()) else {
            return start
        }
        return String(
            localized: "report.range",
            defaultValue: "\(start) to \(end) · \(session.recordedDuration.formattedDuration()) recorded"
        )
    }

    /// Placed above the statistics, not below them.
    ///
    /// If the audio was poor, that is the first thing the reader needs, because
    /// it changes how to read everything after it.
    @ViewBuilder
    private func quality(_ session: NightSession, store: NightReportStore) -> some View {
        if let quality = session.recordingQuality, quality.rating != .excellent {
            SomnaCard {
                Label {
                    Text(qualityTitle(quality.rating))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: quality.rating == .unusable
                          ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(quality.rating == .unusable
                                         ? SomnaColor.error : SomnaColor.warning)
                }

                ForEach(quality.issues, id: \.self) { issue in
                    Text(issue.advice)
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                }

                if quality.coverage < 1 {
                    Text(String(
                        localized: "report.coverage",
                        defaultValue: "\(Int(quality.coverage * 100))% of the session was captured."
                    ))
                    .font(SomnaFont.caption)
                    .foregroundStyle(SomnaColor.textTertiary)
                }
            }
        }
    }

    private func summary(_ session: NightSession) -> some View {
        SomnaCard {
            Text(SummaryRenderer.paragraph(for: session.summaryStatements))
                .font(SomnaFont.body)
                .foregroundStyle(SomnaColor.textPrimary)
        }
    }

    @ViewBuilder
    private func score(_ session: NightSession) -> some View {
        if let value = session.calmnessScore {
            SomnaCard {
                CalmnessRing(score: value)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func statistics(_ session: NightSession) -> some View {
        if let stats = session.statistics {
            SomnaCard {
                Text(String(localized: "report.statistics", defaultValue: "What Somna heard"))
                    .font(SomnaFont.sectionTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                StatusRow(
                    label: String(localized: "report.stat.recorded", defaultValue: "Recorded"),
                    value: stats.recordedDuration.formattedDuration(),
                    state: .neutral
                )
                StatusRow(
                    label: String(localized: "report.stat.quiet", defaultValue: "Nothing detected"),
                    value: stats.quietDuration.formattedDuration(),
                    state: .neutral
                )

                if stats.snoringDuration > 0 {
                    StatusRow(
                        label: String(localized: "report.stat.snoring", defaultValue: "Snoring"),
                        value: stats.snoringDuration.formattedDuration(),
                        state: .neutral
                    )
                }
                if stats.coughCount > 0 {
                    StatusRow(
                        label: String(localized: "report.stat.coughs", defaultValue: "Coughs"),
                        value: "\(stats.coughCount)",
                        state: .neutral
                    )
                }
                if stats.talkingDuration > 0 {
                    StatusRow(
                        label: String(localized: "report.stat.speech", defaultValue: "Speech"),
                        value: stats.talkingDuration.formattedDuration(),
                        state: .neutral
                    )
                }

                if let calmest = stats.calmestPeriod {
                    StatusRow(
                        label: String(localized: "report.stat.calmest", defaultValue: "Quietest stretch"),
                        value: calmest.start.formatted(.dateTime.hour().minute()),
                        state: .neutral
                    )
                }

                // Estimates, and labelled as such. Absent entirely when the
                // evidence was too weak — see `SleepWindowEstimator`.
                if let asleep = session.estimatedSleepStart {
                    StatusRow(
                        label: String(localized: "report.stat.asleep",
                                      defaultValue: "Probably asleep around"),
                        value: asleep.formatted(.dateTime.hour().minute()),
                        state: .neutral
                    )
                }
                if let awake = session.estimatedWakeTime {
                    StatusRow(
                        label: String(localized: "report.stat.awake",
                                      defaultValue: "Probably awake around"),
                        value: awake.formatted(.dateTime.hour().minute()),
                        state: .neutral
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func keyMoments(_ store: NightReportStore) -> some View {
        if !store.keyMoments.isEmpty {
            VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                Text(String(localized: "report.keyMoments", defaultValue: "Worth a listen"))
                    .font(SomnaFont.sectionTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                ForEach(store.keyMoments) { event in
                    EventRow(
                        event: event,
                        isCurrent: player.current?.event.id == event.id,
                        progress: player.current?.event.id == event.id ? player.progress : 0,
                        onPlay: {
                            let items = store.playbackItems()
                            guard let item = items.first(where: { $0.event.id == event.id }) else { return }
                            player.play(item, in: items)
                        },
                        onFavourite: {},
                        onCorrect: { _ in }
                    )
                }
            }
        }
    }

    private func timelineLink(_ store: NightReportStore) -> some View {
        Button(action: onShowTimeline) {
            Text(String(
                localized: "report.seeTimeline",
                defaultValue: "See the whole night (\(store.events.count) events)"
            ))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func qualityTitle(_ rating: RecordingQualityRating) -> String {
        switch rating {
        case .excellent: String(localized: "report.quality.excellent", defaultValue: "Excellent recording")
        case .good: String(localized: "report.quality.good", defaultValue: "Good recording")
        case .poor: String(localized: "report.quality.poor", defaultValue: "The recording had problems")
        case .unusable: String(localized: "report.quality.unusable", defaultValue: "This recording cannot be read")
        }
    }
}
