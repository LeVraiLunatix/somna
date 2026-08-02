import SwiftUI

/// The screen someone opens at bedtime and again at breakfast.
///
/// Three presentations, chosen by what has actually happened rather than by a
/// mode the user has to understand.
struct HomeView: View {

    @Environment(\.somna) private var environment
    @State private var store: HomeStore?

    /// Recording arrives in Phase 5. Until then the primary button explains that
    /// rather than pretending to work — a button that silently does nothing is
    /// worse than one that says why.
    let onStartSession: (() -> Void)?
    let onShowDiagnostics: () -> Void

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("home.root")
        .navigationTitle(Text(verbatim: "Somna"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShowDiagnostics) {
                    Image(systemName: "stethoscope")
                }
                .accessibilityLabel(Text(String(
                    localized: "home.diagnostics",
                    defaultValue: "Diagnostics"
                )))
            }
        }
        .task {
            if store == nil { store = HomeStore(environment: environment) }
            await store?.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(message: String(localized: "home.loading", defaultValue: "Loading…"))
        case .failed(let error):
            ErrorStateView(error: error) { Task { await store?.refresh() } }
        case .ready(let presentation):
            if let store {
                ScrollView {
                    VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                        greeting(store)
                        interrupted(store)
                        presentationContent(presentation)
                        startCard(store)
                    }
                    .padding(SomnaSpacing.l)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    // MARK: - Sections

    private func greeting(_ store: HomeStore) -> some View {
        Text(String(localized: String.LocalizationValue(store.greetingKey),
                    defaultValue: "Good evening"))
            .font(SomnaFont.screenTitle)
            .foregroundStyle(SomnaColor.textPrimary)
    }

    /// Nights that stopped unexpectedly are surfaced first, because their audio
    /// is still on disk and doing nothing about it silently loses it.
    @ViewBuilder
    private func interrupted(_ store: HomeStore) -> some View {
        if !store.unfinishedSessions.isEmpty {
            SomnaCard {
                Label {
                    Text(String(localized: "home.interrupted.title",
                                defaultValue: "A night stopped early"))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SomnaColor.warning)
                }

                Text(String(
                    localized: "home.interrupted.body",
                    defaultValue: "What was recorded before it stopped is still here and can be analysed."
                ))
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func presentationContent(_ presentation: HomeStore.Presentation) -> some View {
        switch presentation {
        case .firstRun:
            SomnaCard {
                Text(String(localized: "home.first.title", defaultValue: "Your first night"))
                    .font(SomnaFont.cardTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                Text(String(
                    localized: "home.first.body",
                    defaultValue: "Put your iPhone within a metre of the bed, plug it in, and start Somna before you fall asleep."
                ))
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)

                Text(String(
                    localized: "home.first.warning",
                    defaultValue: "Do not swipe Somna away from the app switcher during the night — iOS would end the recording for good."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
            }

        case .recentNight(let session), .idle(.some(let session)):
            NightSummaryCard(session: session)

        case .idle(.none):
            EmptyView()
        }
    }

    private func startCard(_ store: HomeStore) -> some View {
        SomnaCard {
            if let issue = store.blockingIssue {
                Label {
                    Text(issue.errorDescription ?? "")
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SomnaColor.warning)
                }

                if let suggestion = issue.recoverySuggestion {
                    Text(suggestion)
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                }
            } else if let onStartSession {
                Button(action: onStartSession) {
                    Text(String(localized: "home.start", defaultValue: "Start tonight"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                // Honest placeholder rather than a dead button.
                Label {
                    Text(String(localized: "home.recordingSoon.title",
                                defaultValue: "Recording is not available yet"))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: "hourglass")
                        .foregroundStyle(SomnaColor.textTertiary)
                }

                Text(String(
                    localized: "home.recordingSoon.body",
                    defaultValue: "This build sets up everything around recording — permissions, storage, calibration. The audio engine itself arrives in the next one."
                ))
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)
            }
        }
    }
}

/// Summary of one night, used on home and later in history.
struct NightSummaryCard: View {

    let session: NightSession

    var body: some View {
        SomnaCard {
            Text(session.startDate.formatted(date: .abbreviated, time: .omitted))
                .font(SomnaFont.cardTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            HStack(spacing: SomnaSpacing.xl) {
                stat(
                    value: session.recordedDuration.formattedCompactDuration,
                    label: String(localized: "home.stat.recorded", defaultValue: "Recorded")
                )

                if let score = session.calmnessScore {
                    stat(
                        value: "\(score)",
                        label: String(localized: "home.stat.calmness", defaultValue: "Calmness")
                    )
                }
            }

            if let summary = session.summary {
                Text(summary)
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
            }

            // The score is an internal indicator, and the report repeats this.
            // Saying it wherever the number appears is the point.
            if session.calmnessScore != nil {
                Text(String(
                    localized: "home.calmnessNote",
                    defaultValue: "Calmness reflects how quiet the recording was. It is not a measure of sleep quality."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: SomnaSpacing.xs) {
            Text(value)
                .font(SomnaFont.statValue)
                .foregroundStyle(SomnaColor.textPrimary)
            Text(label)
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

#if DEBUG
#Preview("First run") {
    NavigationStack {
        HomeView(onStartSession: nil, onShowDiagnostics: {})
    }
    .environment(\.somna, .preview())
}

#Preview("Microphone blocked") {
    NavigationStack {
        HomeView(onStartSession: nil, onShowDiagnostics: {})
    }
    .environment(\.somna, .preview(microphone: .permanentlyDenied))
}
#endif
