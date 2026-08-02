import SwiftUI

/// Temporary root view proving that the generated project produces a running
/// app on a real toolchain.
///
/// Replaced in Phase 3 by the real router, which decides between onboarding and
/// the main app. Strings are intentionally `verbatim`: the brand name and
/// tagline are not localised, and no user-facing copy exists yet — the string
/// catalogue lands with the first real screens in Phase 4.
struct RootView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(verbatim: "Somna")
                    .font(.largeTitle.weight(.semibold))

                Text(verbatim: "Every Night Tells a Story.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(verbatim: "v\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("root.placeholder")
        }
    }
}

#Preview {
    RootView()
}
