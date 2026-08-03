import Foundation
import OSLog
import SwiftUI

/// Measuring the room, outside onboarding.
///
/// The onboarding tells people, in as many words, that calibration can be done
/// later from Settings. Until now that was not true anywhere in the app — and
/// someone who skipped the step, which the onboarding actively encourages in a
/// noisy room, had no way back to it. Without a measured noise floor the
/// detection thresholds fall back to values that match no particular bedroom.
@MainActor
@Observable
final class CalibrationStore {

    enum State: Equatable {
        case idle
        case measuring
        case finished(CalibrationAssessment)
        case failed(AudioError)
    }

    private(set) var state: State = .idle
    private(set) var existing: CalibrationProfile?
    private(set) var microphone: MicrophonePermission = .undetermined

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var canMeasure: Bool {
        microphone.allowsRecording && state != .measuring
    }

    /// Calibration ages: rooms change, phones move, seasons open windows.
    var isStale: Bool {
        guard let existing else { return true }
        return existing.isStale(now: environment.clock.now)
    }

    func load() async {
        microphone = await environment.permissions.microphonePermission()
        existing = try? await environment.sessions.latestCalibration()
    }

    func measure() async {
        guard canMeasure else { return }
        state = .measuring

        do {
            let assessment = try await environment.calibration.measure(
                duration: OnboardingStore.calibrationDuration
            )
            state = .finished(assessment)
            environment.haptics.play(.calibrationFinished)
            await persist(assessment)
        } catch let error as AudioError {
            Log.audio.error("Recalibration failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error)
            environment.haptics.play(.errorOccurred)
        } catch {
            state = .failed(.engineFailedToStart)
            environment.haptics.play(.errorOccurred)
        }
    }

    func openSystemSettings() {
        environment.permissions.openSystemSettings()
    }

    private func persist(_ assessment: CalibrationAssessment) async {
        let profile = CalibrationProfile(
            ambientNoiseFloor: assessment.noiseFloor,
            noiseVariability: assessment.variability,
            placement: .nightstand,
            rating: assessment.rating,
            createdAt: environment.clock.now
        )

        do {
            try await environment.sessions.save(profile)
            existing = profile
        } catch {
            // Surfaced rather than swallowed: someone who just sat silent for
            // fifteen seconds deserves to know it did not take.
            Log.persistence.error("Calibration profile could not be saved")
            state = .failed(.engineFailedToStart)
        }
    }
}

struct CalibrationView: View {

    @Environment(\.somna) private var environment
    @State private var store: CalibrationStore?

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()

            if let store {
                content(store)
            }
        }
        .accessibilityIdentifier("calibration.root")
        .navigationTitle(Text(String(localized: "calibration.title",
                                     defaultValue: "Room calibration")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil { store = CalibrationStore(environment: environment) }
            await store?.load()
        }
    }

    private func content(_ store: CalibrationStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                SomnaCard {
                    Text(String(localized: "calibration.why", defaultValue: "Why this matters"))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)

                    Text(String(
                        localized: "calibration.why.body",
                        defaultValue: "Somna compares every sound to how quiet your room is when nothing is happening. Without that reference it falls back to values that match no particular bedroom, and detection gets noticeably less reliable."
                    ))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                currentState(store)
                measurement(store)
            }
            .padding(SomnaSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func currentState(_ store: CalibrationStore) -> some View {
        SomnaCard {
            if let existing = store.existing {
                StatusRow(
                    label: String(localized: "calibration.current", defaultValue: "Current"),
                    value: ratingTitle(existing.rating),
                    state: existing.rating == .needsImprovement ? .attention : .ok
                )
                StatusRow(
                    label: String(localized: "calibration.measured", defaultValue: "Measured"),
                    value: existing.createdAt.formatted(date: .abbreviated, time: .shortened),
                    state: store.isStale ? .attention : .neutral
                )

                if store.isStale {
                    Text(String(
                        localized: "calibration.stale",
                        defaultValue: "This measurement is over a month old. Rooms change — a new one takes fifteen seconds."
                    ))
                    .font(SomnaFont.caption)
                    .foregroundStyle(SomnaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                StatusRow(
                    label: String(localized: "calibration.current", defaultValue: "Current"),
                    value: String(localized: "calibration.never", defaultValue: "Never measured"),
                    state: .attention
                )
            }
        }
    }

    @ViewBuilder
    private func measurement(_ store: CalibrationStore) -> some View {
        switch store.state {
        case .idle:
            if store.microphone.allowsRecording {
                VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                    Text(String(
                        localized: "calibration.instruction",
                        defaultValue: "Put your iPhone where it spends the night, then stay quiet for fifteen seconds."
                    ))
                    .font(SomnaFont.body)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await store.measure() }
                    } label: {
                        Text(String(localized: "calibration.measure", defaultValue: "Measure now"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                SomnaCard {
                    Text(String(
                        localized: "calibration.needsMicrophone",
                        defaultValue: "Calibration needs the microphone. Allow it in iOS Settings and come back."
                    ))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        store.openSystemSettings()
                    } label: {
                        Text(String(localized: "status.openSettings",
                                    defaultValue: "Open iOS Settings"))
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .measuring:
            LoadingStateView(
                message: String(localized: "calibration.measuring", defaultValue: "Listening…")
            )

        case .finished(let assessment):
            result(assessment, store: store)

        case .failed(let error):
            SomnaCard {
                Label {
                    Text(error.errorDescription ?? "")
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SomnaColor.warning)
                }

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await store.measure() }
                } label: {
                    Text(String(localized: "action.retry", defaultValue: "Try again"))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func result(_ assessment: CalibrationAssessment, store: CalibrationStore) -> some View {
        SomnaCard {
            Label {
                Text(ratingTitle(assessment.rating))
                    .font(SomnaFont.cardTitle)
                    .foregroundStyle(SomnaColor.textPrimary)
            } icon: {
                Image(systemName: assessment.rating == .needsImprovement
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(assessment.rating == .needsImprovement
                                     ? SomnaColor.warning : SomnaColor.success)
            }

            ForEach(assessment.issues, id: \.self) { issue in
                Text(String.localized(dynamicKey: issue.adviceKey, fallback: issue.englishAdvice))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if assessment.issues.isEmpty {
                Text(String(localized: "onboarding.calibration.allGood",
                            defaultValue: "This spot works well. You are ready for tonight."))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await store.measure() }
            } label: {
                Text(String(localized: "calibration.again", defaultValue: "Measure again"))
            }
            .buttonStyle(.bordered)
        }
    }

    private func ratingTitle(_ rating: CalibrationProfile.Rating) -> String {
        switch rating {
        case .excellent: String(localized: "calibration.rating.excellent", defaultValue: "Excellent placement")
        case .good: String(localized: "calibration.rating.good", defaultValue: "Good placement")
        case .needsImprovement: String(localized: "calibration.rating.improve", defaultValue: "Could be better")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { CalibrationView() }
        .environment(\.somna, .preview())
}
#endif
