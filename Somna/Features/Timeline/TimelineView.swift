import SwiftUI

/// The night, event by event.
struct TimelineView: View {

    @Environment(\.somna) private var environment
    @Environment(ClipPlayer.self) private var player
    @State private var store: TimelineStore?

    let sessionID: UUID

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("timeline.root")
        .navigationTitle(Text(String(localized: "timeline.title", defaultValue: "Timeline")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = TimelineStore(environment: environment, sessionID: sessionID)
            }
            await store?.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(message: String(localized: "timeline.loading",
                                             defaultValue: "Loading your night…"))
        case .failed(let error):
            ErrorStateView(error: error) { Task { await store?.load() } }
        case .ready:
            if let store {
                if store.allEvents.isEmpty {
                    quietNight
                } else {
                    list(store)
                }
            }
        }
    }

    /// A night with nothing detected is a result, not an absence.
    ///
    /// It is also ambiguous, and the copy says so rather than congratulating
    /// someone on a quiet night that may have been a deaf microphone.
    private var quietNight: some View {
        VStack(spacing: SomnaSpacing.m) {
            Image(systemName: "moon.zzz")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(SomnaColor.textTertiary)
                .accessibilityHidden(true)

            Text(String(localized: "timeline.empty.title", defaultValue: "Nothing was detected"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(
                localized: "timeline.empty.body",
                defaultValue: "Either the night was remarkably quiet, or the microphone was not picking much up. The recording quality section says which is more likely."
            ))
            .font(SomnaFont.secondary)
            .foregroundStyle(SomnaColor.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(SomnaSpacing.xl)
    }

    private func list(_ store: TimelineStore) -> some View {
        @Bindable var store = store

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: SomnaSpacing.m, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(store.events) { event in
                        EventRow(
                            event: event,
                            isCurrent: player.current?.event.id == event.id,
                            progress: player.current?.event.id == event.id ? player.progress : 0,
                            onPlay: { play(event, from: store) },
                            onFavourite: { Task { await store.toggleFavourite(event) } },
                            onCorrect: { type in Task { await store.correct(event, to: type) } }
                        )
                    }
                } header: {
                    filters(store)
                }
            }
            .padding(SomnaSpacing.l)
            // Room for the floating player, so the last row is never hidden
            // behind it.
            .padding(.bottom, player.current == nil ? 0 : 96)
        }
    }

    private func filters(_ store: TimelineStore) -> some View {
        @Bindable var store = store

        return ScrollView(.horizontal) {
            HStack(spacing: SomnaSpacing.s) {
                ForEach(store.availableFilters) { filter in
                    Button {
                        store.filter = filter
                    } label: {
                        Text(title(for: filter))
                            .font(SomnaFont.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(store.filter == filter ? SomnaColor.accentPrimary : SomnaColor.textTertiary)
                }
            }
            .padding(.vertical, SomnaSpacing.s)
        }
        .scrollIndicators(.hidden)
        .background(SomnaColor.backgroundPrimary)
    }

    private func play(_ event: NightEvent, from store: TimelineStore) {
        let items = store.playbackItems()
        guard let item = items.first(where: { $0.event.id == event.id }) else { return }
        player.play(item, in: items)
    }

    private func title(for filter: TimelineStore.Filter) -> String {
        switch filter {
        case .all: String(localized: "timeline.filter.all", defaultValue: "All")
        case .snoring: String(localized: "timeline.filter.snoring", defaultValue: "Snoring")
        case .coughing: String(localized: "timeline.filter.coughing", defaultValue: "Coughing")
        case .speech: String(localized: "timeline.filter.speech", defaultValue: "Speech")
        case .environment: String(localized: "timeline.filter.environment", defaultValue: "Around you")
        case .favourites: String(localized: "timeline.filter.favourites", defaultValue: "Saved")
        }
    }
}

/// One event.
struct EventRow: View {

    let event: NightEvent
    let isCurrent: Bool
    let progress: Double
    let onPlay: () -> Void
    let onFavourite: () -> Void
    let onCorrect: (NightEventType) -> Void

    var body: some View {
        SomnaCard {
            HStack(alignment: .top, spacing: SomnaSpacing.m) {
                Image(systemName: event.effectiveType.symbolName)
                    .font(.system(.body))
                    .foregroundStyle(SomnaColor.confidence(event.effectiveConfidence))
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SomnaSpacing.xs) {
                    Text(event.title)
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)

                    Text(subtitle)
                        .font(SomnaFont.caption)
                        .foregroundStyle(SomnaColor.textSecondary)
                }

                Spacer(minLength: SomnaSpacing.s)

                Text(event.startDate.formatted(.dateTime.hour().minute()))
                    .font(SomnaFont.timestamp)
                    .foregroundStyle(SomnaColor.textSecondary)
            }

            if event.hasPlayableClip {
                HStack(spacing: SomnaSpacing.m) {
                    Button(action: onPlay) {
                        Image(systemName: isCurrent ? "waveform" : "play.circle.fill")
                            .font(.system(.title2))
                            .foregroundStyle(SomnaColor.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: SomnaSpacing.minimumTapTarget,
                           height: SomnaSpacing.minimumTapTarget)
                    .accessibilityLabel(Text(String(
                        localized: "timeline.play",
                        defaultValue: "Listen to this moment"
                    )))

                    MiniWaveform(samples: event.waveformSamples, progress: isCurrent ? progress : 0)
                        .frame(height: 28)
                }
            } else {
                // Stated rather than hidden: an event without audio is one the
                // user cannot check, and that changes how much to trust it.
                Text(String(
                    localized: "timeline.noClip",
                    defaultValue: "The audio for this moment is no longer stored."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
            }
        }
        .contextMenu {
            Button(action: onFavourite) {
                Label(
                    event.isFavorite
                        ? String(localized: "timeline.unsave", defaultValue: "Remove from saved")
                        : String(localized: "timeline.save", defaultValue: "Save this moment"),
                    systemImage: event.isFavorite ? "bookmark.slash" : "bookmark"
                )
            }

            Menu {
                ForEach(NightEventType.userCorrectable, id: \.self) { type in
                    Button {
                        onCorrect(type)
                    } label: {
                        Label(
                            NightEventPhrasing.title(for: type, confidence: .high),
                            systemImage: type.symbolName
                        )
                    }
                }
            } label: {
                Label(
                    String(localized: "timeline.correct", defaultValue: "This was actually…"),
                    systemImage: "pencil"
                )
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []

        if event.isGrouped {
            parts.append(String(
                localized: "timeline.episodes",
                defaultValue: "\(event.occurrenceCount) episodes"
            ))
        }
        if event.duration >= 1 {
            parts.append(event.duration.formattedDuration())
        }
        if event.userCorrectedType != nil {
            // Marked so the user can see which rows they changed, and so a
            // correction never masquerades as the model having been right.
            parts.append(String(localized: "timeline.corrected", defaultValue: "corrected by you"))
        }

        return parts.joined(separator: " · ")
    }
}
