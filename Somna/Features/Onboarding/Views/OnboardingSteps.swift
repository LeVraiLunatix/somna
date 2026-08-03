import SwiftUI

// The seven onboarding steps. Content only — navigation belongs to
// `OnboardingView`, so no step can create a shortcut past an explanation.

struct WelcomeStepView: View {
    var body: some View {
        OnboardingStepLayout(
            symbolName: "moon.stars",
            title: String(localized: "onboarding.welcome.title", defaultValue: "Somna"),
            subtitle: String(localized: "onboarding.welcome.tagline",
                             defaultValue: "Every night tells a story.")
        ) {
            Text(String(
                localized: "onboarding.welcome.body",
                defaultValue: "Somna listens while you sleep and builds a timeline of what happened, so you can hear it for yourself in the morning."
            ))
            .font(SomnaFont.body)
            .foregroundStyle(SomnaColor.textSecondary)
        }
    }
}

struct HowItWorksStepView: View {
    var body: some View {
        OnboardingStepLayout(
            symbolName: "waveform",
            title: String(localized: "onboarding.how.title", defaultValue: "How it works"),
            subtitle: String(localized: "onboarding.how.subtitle",
                             defaultValue: "Three things, once a night.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                OnboardingPoint(
                    symbolName: "1.circle.fill",
                    text: String(localized: "onboarding.how.step1",
                                 defaultValue: "Start Somna before you go to sleep.")
                )
                OnboardingPoint(
                    symbolName: "2.circle.fill",
                    text: String(localized: "onboarding.how.step2",
                                 defaultValue: "Leave your iPhone near the bed, plugged in.")
                )
                OnboardingPoint(
                    symbolName: "3.circle.fill",
                    text: String(localized: "onboarding.how.step3",
                                 defaultValue: "Read your night in the morning.")
                )
            }
        }
    }
}

/// The honesty step.
///
/// It exists because every claim Somna makes later is only trustworthy if the
/// limits were stated first. Putting this *before* asking for the microphone is
/// deliberate: someone should be able to decline once they know what it cannot do.
struct CapabilitiesStepView: View {
    var body: some View {
        OnboardingStepLayout(
            symbolName: "checkmark.seal",
            title: String(localized: "onboarding.limits.title", defaultValue: "What Somna can and cannot do"),
            subtitle: String(localized: "onboarding.limits.subtitle",
                             defaultValue: "Worth knowing before you rely on it.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                OnboardingPoint(
                    symbolName: "checkmark.circle.fill",
                    text: String(localized: "onboarding.limits.can",
                                 defaultValue: "It detects likely sounds: snoring, coughing, speech, doors, rain."),
                    tint: SomnaColor.success
                )
                OnboardingPoint(
                    symbolName: "xmark.circle.fill",
                    text: String(localized: "onboarding.limits.noCamera",
                                 defaultValue: "It never uses the camera."),
                    tint: SomnaColor.textTertiary
                )
                OnboardingPoint(
                    symbolName: "xmark.circle.fill",
                    text: String(localized: "onboarding.limits.noMovement",
                                 defaultValue: "It cannot tell how you moved, only what it heard."),
                    tint: SomnaColor.textTertiary
                )
                OnboardingPoint(
                    symbolName: "xmark.circle.fill",
                    text: String(localized: "onboarding.limits.noMedical",
                                 defaultValue: "It is not a medical device and makes no diagnosis."),
                    tint: SomnaColor.textTertiary
                )
                OnboardingPoint(
                    symbolName: "exclamationmark.circle.fill",
                    text: String(localized: "onboarding.limits.mistakes",
                                 defaultValue: "It gets things wrong sometimes. Every event keeps its audio so you can check."),
                    tint: SomnaColor.warning
                )

                // Two people in a bedroom cannot be told apart by a microphone.
                // Saying so here prevents the most damaging misreading of a report.
                Text(String(
                    localized: "onboarding.limits.sharedRoom",
                    defaultValue: "If you share a room, Somna cannot tell who made a sound. It will say “snoring detected”, never “you snored”."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
            }
        }
    }
}

struct PrivacyStepView: View {
    var body: some View {
        OnboardingStepLayout(
            symbolName: "lock.shield",
            title: String(localized: "onboarding.privacy.title", defaultValue: "Everything stays on this iPhone"),
            subtitle: String(localized: "onboarding.privacy.subtitle",
                             defaultValue: "No account, no server, no uploads.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                OnboardingPoint(
                    symbolName: "iphone",
                    text: String(localized: "onboarding.privacy.local",
                                 defaultValue: "Recordings are stored in Somna's own folder, encrypted by iOS.")
                )
                OnboardingPoint(
                    symbolName: "clock.arrow.circlepath",
                    text: String(localized: "onboarding.privacy.retention",
                                 defaultValue: "Raw audio is deleted after seven days by default. You choose.")
                )
                OnboardingPoint(
                    symbolName: "text.bubble",
                    text: String(localized: "onboarding.privacy.noTranscription",
                                 defaultValue: "Somna never transcribes what is said — yours or anyone else's.")
                )
                OnboardingPoint(
                    symbolName: "trash",
                    text: String(localized: "onboarding.privacy.deletion",
                                 defaultValue: "You can erase everything at any time from Settings.")
                )
            }
        }
    }
}

struct MicrophoneStepView: View {

    let store: OnboardingStore

    var body: some View {
        OnboardingStepLayout(
            symbolName: "mic",
            title: String(localized: "onboarding.mic.title", defaultValue: "Somna needs the microphone"),
            subtitle: String(localized: "onboarding.mic.subtitle",
                             defaultValue: "It is the only sensor Somna uses.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                switch store.microphone {
                case .undetermined:
                    Button {
                        Task { await store.requestMicrophone() }
                    } label: {
                        Text(String(localized: "onboarding.mic.allow",
                                    defaultValue: "Allow microphone access"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isRequestingPermission)

                case .granted:
                    Label {
                        Text(String(localized: "onboarding.mic.granted",
                                    defaultValue: "Microphone access allowed"))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SomnaColor.success)
                    }
                    .font(SomnaFont.bodyEmphasis)
                    .foregroundStyle(SomnaColor.textPrimary)

                case .denied, .permanentlyDenied:
                    // Somna keeps working as a reader of past nights, so this is
                    // stated as a consequence, not as an error the user must fix
                    // before being allowed to continue.
                    VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                        Text(String(
                            localized: "onboarding.mic.denied",
                            defaultValue: "Without the microphone, Somna cannot record a night. You can still browse nights you have already recorded."
                        ))
                        .font(SomnaFont.body)
                        .foregroundStyle(SomnaColor.textSecondary)

                        Button {
                            store.openSystemSettings()
                        } label: {
                            Text(String(localized: "status.openSettings",
                                        defaultValue: "Open iOS Settings"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
        }
    }
}

struct NotificationsStepView: View {

    let store: OnboardingStore

    var body: some View {
        OnboardingStepLayout(
            symbolName: "bell.badge",
            title: String(localized: "onboarding.notifications.title", defaultValue: "Gentle reminders"),
            subtitle: String(localized: "onboarding.notifications.subtitle",
                             defaultValue: "Entirely optional. Somna works without them.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.m) {
                OnboardingPoint(
                    symbolName: "moon",
                    text: String(localized: "onboarding.notifications.evening",
                                 defaultValue: "An evening nudge, if you want one.")
                )
                OnboardingPoint(
                    symbolName: "sun.horizon",
                    text: String(localized: "onboarding.notifications.morning",
                                 defaultValue: "Your report, when it is ready.")
                )

                if store.notifications == .undetermined {
                    Button {
                        Task { await store.requestNotifications() }
                    } label: {
                        Text(String(localized: "onboarding.notifications.allow",
                                    defaultValue: "Allow notifications"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(store.isRequestingPermission)
                } else {
                    Text(store.notifications == .granted
                         ? String(localized: "onboarding.notifications.on", defaultValue: "Notifications are on.")
                         : String(localized: "onboarding.notifications.off",
                                  defaultValue: "Notifications are off. You can turn them on later in Settings."))
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                }
            }
        }
    }
}

struct CalibrationStepView: View {

    @Environment(\.somnaPalette) private var palette

    let store: OnboardingStore

    var body: some View {
        OnboardingStepLayout(
            symbolName: "dial.medium",
            title: String(localized: "onboarding.calibration.title", defaultValue: "Measure your room"),
            subtitle: String(localized: "onboarding.calibration.subtitle",
                             defaultValue: "Fifteen seconds of quiet, so Somna knows what quiet sounds like here.")
        ) {
            VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                Text(String(
                    localized: "onboarding.calibration.instruction",
                    defaultValue: "Put your iPhone where it will spend the night, then stay quiet."
                ))
                .font(SomnaFont.body)
                .foregroundStyle(SomnaColor.textSecondary)

                switch store.calibration {
                case .idle:
                    if store.microphone.allowsRecording {
                        Button {
                            Task { await store.runCalibration() }
                        } label: {
                            Text(String(localized: "onboarding.calibration.start",
                                        defaultValue: "Measure now"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Text(String(
                            localized: "onboarding.calibration.needsMic",
                            defaultValue: "Calibration needs the microphone. You can do it later from Settings."
                        ))
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                    }

                case .measuring:
                    LoadingStateView(
                        message: String(localized: "onboarding.calibration.measuring",
                                        defaultValue: "Listening…")
                    )

                case .finished(let assessment):
                    result(assessment)

                case .failed(let error):
                    // A failed measurement is not a blocked onboarding: the
                    // button below still says "Skip for now", and calibration
                    // can be redone from Settings whenever the room allows.
                    SomnaCard {
                        Label {
                            Text(error.errorDescription ?? "")
                                .font(SomnaFont.cardTitle)
                                .foregroundStyle(SomnaColor.textPrimary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SomnaColor.warning)
                        }

                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(SomnaFont.secondary)
                                .foregroundStyle(SomnaColor.textSecondary)
                        }

                        Button {
                            Task { await store.runCalibration() }
                        } label: {
                            Text(String(localized: "action.retry", defaultValue: "Try again"))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func result(_ assessment: CalibrationAssessment) -> some View {
        SomnaCard {
            Label {
                Text(ratingTitle(assessment.rating))
                    .font(SomnaFont.cardTitle)
                    .foregroundStyle(SomnaColor.textPrimary)
            } icon: {
                Image(systemName: ratingSymbol(assessment.rating))
                    .foregroundStyle(ratingTint(assessment.rating))
            }

            // Advice, not a verdict: a rating nobody can act on only makes
            // people distrust the app.
            ForEach(assessment.issues, id: \.self) { issue in
                Text(String.localized(dynamicKey: issue.adviceKey,
                                      fallback: issue.englishAdvice))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
            }

            if assessment.issues.isEmpty {
                Text(String(localized: "onboarding.calibration.allGood",
                            defaultValue: "This spot works well. You are ready for tonight."))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
            }
        }
    }

    private func ratingTitle(_ rating: CalibrationProfile.Rating) -> String {
        switch rating {
        case .excellent: String(localized: "calibration.rating.excellent", defaultValue: "Excellent placement")
        case .good: String(localized: "calibration.rating.good", defaultValue: "Good placement")
        case .needsImprovement: String(localized: "calibration.rating.improve", defaultValue: "Could be better")
        }
    }

    private func ratingSymbol(_ rating: CalibrationProfile.Rating) -> String {
        switch rating {
        case .excellent, .good: "checkmark.circle.fill"
        case .needsImprovement: "exclamationmark.triangle.fill"
        }
    }

    private func ratingTint(_ rating: CalibrationProfile.Rating) -> Color {
        switch rating {
        case .excellent: SomnaColor.success
        case .good: palette.accentPrimary
        case .needsImprovement: SomnaColor.warning
        }
    }
}
