import SwiftUI

/// The seven-step first run.
///
/// One container owning navigation and progress, with each step contributing
/// only its content. Steps cannot navigate themselves, which is what keeps the
/// sequence from developing shortcuts that skip a permission explanation.
struct OnboardingView: View {

    @Environment(\.somna) private var environment
    @State private var store: OnboardingStore?

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()

            if let store {
                content(store)
            }
        }
        .accessibilityIdentifier("onboarding.root")
        .task {
            if store == nil { store = OnboardingStore(environment: environment) }
            await store?.start()
        }
        .onChange(of: store?.hasFinished ?? false) { _, finished in
            if finished { onFinished() }
        }
    }

    private func content(_ store: OnboardingStore) -> some View {
        VStack(spacing: 0) {
            // The step is shown rather than hidden inside the bar's label.
            // A four-point progress bar carrying an accessibility label is an
            // element the audit measures as an undersized hit region — and
            // sighted users benefit from seeing where they are just as much.
            VStack(spacing: SomnaSpacing.xs) {
                ProgressView(value: store.progress)
                    .tint(SomnaColor.accentPrimary)
                    .accessibilityHidden(true)

                Text(String(
                    localized: "onboarding.progress",
                    defaultValue: "Step \(store.step.rawValue + 1) of \(OnboardingStore.Step.allCases.count)"
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, SomnaSpacing.l)

            ScrollView {
                stepContent(store)
                    .padding(SomnaSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer(store)
        }
        .somnaAnimation(value: store.step)
    }

    @ViewBuilder
    private func stepContent(_ store: OnboardingStore) -> some View {
        switch store.step {
        case .welcome: WelcomeStepView()
        case .howItWorks: HowItWorksStepView()
        case .capabilities: CapabilitiesStepView()
        case .privacy: PrivacyStepView()
        case .microphone: MicrophoneStepView(store: store)
        case .notifications: NotificationsStepView(store: store)
        case .calibration: CalibrationStepView(store: store)
        }
    }

    private func footer(_ store: OnboardingStore) -> some View {
        VStack(spacing: SomnaSpacing.m) {
            Button {
                store.advance()
            } label: {
                Text(primaryTitle(store))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canAdvance)

            if store.step != .welcome {
                Button {
                    store.goBack()
                } label: {
                    Text(String(localized: "action.back", defaultValue: "Back"))
                        // A plain button is only as tappable as its label. The
                        // audit measured this one under 44 points high, which on
                        // the step where someone wants to go back and re-read is
                        // exactly where a missed tap is most frustrating.
                        .frame(minHeight: SomnaSpacing.minimumTapTarget)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SomnaColor.textSecondary)
            }
        }
        .padding(SomnaSpacing.l)
        .background(SomnaColor.backgroundPrimary)
    }

    private func primaryTitle(_ store: OnboardingStore) -> String {
        switch store.step {
        case .calibration:
            switch store.calibration {
            case .finished, .failed:
                String(localized: "onboarding.finish", defaultValue: "Start using Somna")
            default:
                String(localized: "onboarding.skip", defaultValue: "Skip for now")
            }
        default:
            String(localized: "action.continue", defaultValue: "Continue")
        }
    }
}

// MARK: - Shared layout

/// Common shape for every step, so the sequence reads as one thing rather than
/// seven screens that happen to follow each other.
struct OnboardingStepLayout<Content: View>: View {

    let symbolName: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SomnaSpacing.l) {
            Image(systemName: symbolName)
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(SomnaColor.accentPrimary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SomnaSpacing.s) {
                Text(title)
                    .font(SomnaFont.screenTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                Text(subtitle)
                    .font(SomnaFont.body)
                    .foregroundStyle(SomnaColor.textSecondary)
            }

            content
        }
    }
}

/// A numbered or bulleted point inside a step.
struct OnboardingPoint: View {

    let symbolName: String
    let text: String
    var tint: Color = SomnaColor.accentPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SomnaSpacing.m) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(text)
                .font(SomnaFont.body)
                .foregroundStyle(SomnaColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    OnboardingView(onFinished: {})
        .environment(\.somna, .preview(microphone: .undetermined, notifications: .undetermined))
}
#endif
