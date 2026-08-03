import SwiftUI

/// Shown when there is genuinely nothing yet.
///
/// An empty state must always offer a way forward. A screen that says "no data"
/// and stops is a dead end, and this component makes the action a required
/// parameter rather than an optional courtesy.
struct EmptyStateView: View {

    let symbolName: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: SomnaSpacing.l) {
            Image(systemName: symbolName)
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(SomnaColor.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: SomnaSpacing.s) {
                Text(title)
                    .font(SomnaFont.sectionTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                Text(message)
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(SomnaSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Shown when something failed.
///
/// Takes a `SomnaError` rather than a string so the message and the suggested
/// remedy always come from the same place — the error itself, which is where the
/// context to write them actually lives.
struct ErrorStateView: View {

    let error: SomnaError
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: SomnaSpacing.l) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(SomnaColor.warning)
                .accessibilityHidden(true)

            VStack(spacing: SomnaSpacing.s) {
                Text(error.errorDescription ?? "")
                    .font(SomnaFont.sectionTitle)
                    .foregroundStyle(SomnaColor.textPrimary)
                    .multilineTextAlignment(.center)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let retry {
                Button(String(localized: "action.retry", defaultValue: "Try again"), action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(SomnaSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Shown while work is in progress.
struct LoadingStateView: View {

    let message: String

    var body: some View {
        VStack(spacing: SomnaSpacing.m) {
            ProgressView()
            Text(message)
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)
        }
        .padding(SomnaSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
