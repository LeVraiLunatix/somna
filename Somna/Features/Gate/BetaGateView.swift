import Foundation
import SwiftUI

/// The private-beta gate.
///
/// Shown once, after the launch sequence and before anything else. Unlocking is
/// remembered, so nobody types a code every morning at 6 a.m.
@MainActor
@Observable
final class BetaGateStore {

    private(set) var isChecking = false
    private(set) var showsRejection = false

    var code = ""

    /// Deliberately generous, and deliberately slowed rather than locked.
    ///
    /// Someone mistyping a code they were legitimately given must never be shut
    /// out of an app they installed — the failure mode of a lockout is a tester
    /// who gives up, which costs more than the brute-force it would prevent on a
    /// gate that is not security in the first place.
    private(set) var attempts = 0
    private static let delayAfterAttempts = 5

    private let appSettings: AppSettings
    private let haptics: any HapticFeedbacking

    init(appSettings: AppSettings, haptics: any HapticFeedbacking) {
        self.appSettings = appSettings
        self.haptics = haptics
    }

    var canSubmit: Bool {
        !isChecking && !BetaAccessCode.normalise(code).isEmpty
    }

    func submit() async {
        guard canSubmit else { return }

        isChecking = true
        showsRejection = false
        defer { isChecking = false }

        // A small, growing pause once someone has clearly started guessing.
        // Enough to make an automated sweep tedious, short enough that a person
        // who fat-fingered their code twice does not notice.
        if attempts >= Self.delayAfterAttempts {
            try? await Task.sleep(for: .milliseconds(600))
        }

        guard BetaAccessCode.matches(code) else {
            attempts += 1
            showsRejection = true
            haptics.play(.errorOccurred)
            return
        }

        haptics.play(.calibrationFinished)
        appSettings.update { $0.hasUnlockedBeta = true }
    }
}

struct BetaGateView: View {

    @Environment(\.somna) private var environment
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.somnaPalette) private var palette
    @FocusState private var isFieldFocused: Bool
    @State private var store: BetaGateStore?

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()

            if let store {
                content(store)
            }
        }
        .accessibilityIdentifier("gate.root")
        .task {
            if store == nil {
                store = BetaGateStore(appSettings: appSettings, haptics: environment.haptics)
            }
            isFieldFocused = true
        }
    }

    private func content(_ store: BetaGateStore) -> some View {
        @Bindable var store = store

        return ScrollView {
            VStack(spacing: SomnaSpacing.l) {
                Image(systemName: "moon.stars")
                    .font(.system(.largeTitle, weight: .light))
                    .foregroundStyle(palette.accentPrimary)
                    .accessibilityHidden(true)

                VStack(spacing: SomnaSpacing.s) {
                    Text(String(localized: "gate.title", defaultValue: "Private beta"))
                        .font(SomnaFont.screenTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(
                        localized: "gate.body",
                        defaultValue: "This build is being tested by a small group. Enter the code you were given to continue."
                    ))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                SecureField(
                    String(localized: "gate.field", defaultValue: "Access code"),
                    text: $store.code
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFieldFocused)
                .onSubmit { Task { await store.submit() } }
                .frame(maxWidth: 320)

                if store.showsRejection {
                    Label {
                        Text(String(localized: "gate.rejected",
                                    defaultValue: "That code does not open this build."))
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await store.submit() }
                } label: {
                    Text(String(localized: "gate.enter", defaultValue: "Enter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.canSubmit)
                .frame(maxWidth: 320)

                // Said plainly, because a password field invites the wrong
                // assumption. Someone must not conclude their recordings are
                // protected by this — they are protected by never leaving the
                // device, which is a different and much stronger thing.
                Text(String(
                    localized: "gate.disclaimer",
                    defaultValue: "This code decides who joins the beta. It does not protect your recordings — those never leave your iPhone, and iOS encrypts them on disk."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SomnaSpacing.m)
            }
            .padding(SomnaSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#if DEBUG
#Preview {
    let environment = AppEnvironment.preview()
    return BetaGateView()
        .environment(\.somna, environment)
        .environment(AppSettings(
            repository: environment.settings,
            notifications: environment.notifications
        ))
}
#endif
