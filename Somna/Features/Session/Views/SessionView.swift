import SwiftUI

/// Preparation, then the running night, then the handover.
///
/// One screen rather than three, because it is one continuous act: nobody
/// "navigates" from getting ready to sleeping. Splitting it would also have
/// duplicated the store that owns the recording.
struct SessionView: View {

    @Environment(\.somna) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var store: SessionStore?

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("session.root")
        .navigationTitle(Text(String(localized: "session.title", defaultValue: "Tonight")))
        .navigationBarBackButtonHidden(store?.isRunning == true)
        .interactiveDismissDisabled(store?.isRunning == true)
        .task {
            if store == nil { store = SessionStore(environment: environment) }
            await store?.runPreflight()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            switch store.phase {
            case .preparing:
                preparation(store)
            case .starting:
                LoadingStateView(message: String(localized: "session.starting",
                                                 defaultValue: "Starting…"))
            case .running, .stopping:
                RunningSessionView(store: store)
            case .analysing(let progress):
                analysing(progress)
            case .finished(let session):
                finished(session)
            case .failed(let error):
                ErrorStateView(error: error) {
                    Task { await store.runPreflight() }
                }
            }
        }
    }

    // MARK: - Preparation

    private func preparation(_ store: SessionStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                SomnaCard {
                    Text(String(localized: "session.prepare.title",
                                defaultValue: "Before you sleep"))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)

                    Text(String(
                        localized: "session.prepare.body",
                        defaultValue: "Somna will listen until you stop it. It keeps recording with the screen locked."
                    ))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)

                    // The one thing iOS cannot protect against, so it is said
                    // where the decision is made rather than buried in Settings.
                    Text(String(
                        localized: "session.prepare.warning",
                        defaultValue: "Do not swipe Somna away from the app switcher — iOS would end the recording permanently."
                    ))
                    .font(SomnaFont.caption)
                    .foregroundStyle(SomnaColor.warning)
                }

                SomnaCard {
                    Text(String(localized: "session.checklist", defaultValue: "Checklist"))
                        .font(SomnaFont.sectionTitle)
                        .foregroundStyle(SomnaColor.textPrimary)

                    ForEach(store.checks) { check in
                        StatusRow(
                            label: check.title,
                            value: check.detail,
                            state: state(for: check.severity)
                        )
                    }

                    StatusRow(
                        label: String(localized: "session.estimatedSize",
                                      defaultValue: "A full night uses about"),
                        value: store.estimatedNightSize.formattedByteSize,
                        state: .neutral
                    )
                }

                Button {
                    Task { await store.start() }
                } label: {
                    Text(String(localized: "session.start", defaultValue: "Begin the night"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.canStart)
            }
            .padding(SomnaSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func state(for severity: SessionStore.Check.Severity) -> StatusRow.State {
        switch severity {
        case .satisfied: .ok
        case .advisory: .attention
        case .blocking: .problem
        }
    }

    // MARK: - Analysing

    private func analysing(_ progress: AnalysisProgress) -> some View {
        VStack(spacing: SomnaSpacing.l) {
            ProgressView(value: progress.fraction)
                .tint(SomnaColor.accentPrimary)
                .padding(.horizontal, SomnaSpacing.xl)

            Text(String(localized: "session.analysing", defaultValue: "Reading your night…"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            Text(String(
                localized: "session.analysing.detail",
                defaultValue: "Somna is going back over the parts where it heard something. This takes a couple of minutes."
            ))
            .font(SomnaFont.secondary)
            .foregroundStyle(SomnaColor.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(SomnaSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Finished

    private func finished(_ session: NightSession) -> some View {
        VStack(spacing: SomnaSpacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(SomnaColor.success)
                .accessibilityHidden(true)

            Text(String(localized: "session.finished.title", defaultValue: "Night recorded"))
                .font(SomnaFont.screenTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            Text(String(
                localized: "session.finished.duration",
                defaultValue: "\(session.recordedDuration.formattedCompactDuration) of audio captured"
            ))
            .font(SomnaFont.body)
            .foregroundStyle(SomnaColor.textSecondary)

            if !session.summaryStatements.isEmpty {
                Text(SummaryRenderer.paragraph(for: session.summaryStatements))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
            } label: {
                Text(String(localized: "action.done", defaultValue: "Done"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(SomnaSpacing.xl)
    }
}

/// What the screen shows while a night is being recorded.
///
/// Deliberately sparse and dark. It is looked at in a dark bedroom by someone
/// about to sleep, and again at 3 a.m. by someone who should go back to sleep.
struct RunningSessionView: View {

    let store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: SomnaSpacing.xl) {
            Spacer()

            VStack(spacing: SomnaSpacing.s) {
                Text(stateTitle)
                    .font(SomnaFont.sectionTitle)
                    .foregroundStyle(SomnaColor.textSecondary)

                Text(store.status.recordedDuration.formattedCompactDuration)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SomnaColor.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(String(
                        localized: "session.elapsed",
                        defaultValue: "Recording for \(store.status.recordedDuration.formattedDuration())"
                    )))
            }

            levelMeter

            if case .interrupted = store.status.state {
                // Never hidden. A gap the user does not know about turns into a
                // report that quietly under-reports their night.
                Label {
                    Text(String(localized: "session.interrupted",
                                defaultValue: "Interrupted — Somna is trying to resume"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.warning)
            }

            Spacer()

            Button(role: .destructive) {
                Task { await store.stop() }
            } label: {
                Text(String(localized: "session.stop", defaultValue: "End the night"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.phase == .stopping)
            .padding(.horizontal, SomnaSpacing.l)
            .padding(.bottom, SomnaSpacing.xl)
        }
    }

    private var stateTitle: String {
        switch store.status.state {
        case .interrupted, .resuming:
            String(localized: "session.state.interrupted", defaultValue: "Paused by iOS")
        default:
            String(localized: "session.state.listening", defaultValue: "Listening")
        }
    }

    /// A quiet level indicator rather than a live waveform.
    ///
    /// A waveform would be a bright, constantly moving light source in a dark
    /// bedroom, and it would keep the display awake. This shows that something
    /// is being heard, which is all the reassurance the moment needs.
    private var levelMeter: some View {
        let level = Double(store.status.level)

        return Circle()
            .fill(SomnaColor.accentPrimary.opacity(0.18 + min(0.5, level * 2)))
            .frame(width: 120, height: 120)
            .overlay(
                Circle()
                    .strokeBorder(SomnaColor.accentPrimary.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1 : 1 + min(0.12, level))
            .somnaAnimation(SomnaMotion.quick, value: store.status.level)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Preparation") {
    NavigationStack { SessionView() }
        .environment(\.somna, .preview())
}

#Preview("Not charging") {
    NavigationStack { SessionView() }
        .environment(\.somna, .preview(power: 0.22, isCharging: false))
}

#Preview("Microphone blocked") {
    NavigationStack { SessionView() }
        .environment(\.somna, .preview(microphone: .permanentlyDenied))
}
#endif
