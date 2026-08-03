import SwiftUI

/// What Somna might become. Nothing here is purchasable.
///
/// The screen exists because a private beta is the right moment to ask testers
/// whether these are the things they would actually want. It shows no price, no
/// button, and no trial: a disabled purchase flow that looks real is a dark
/// pattern, and a fake price is a promise.
struct PremiumView: View {

    @Environment(\.somnaPalette) private var palette

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private var features: [Feature] {
        [
            Feature(
                symbol: "infinity",
                title: String(localized: "premium.history.title", defaultValue: "Unlimited history"),
                detail: String(localized: "premium.history.detail",
                               defaultValue: "Keep every night, instead of the most recent ones.")
            ),
            Feature(
                symbol: "chart.xyaxis.line",
                title: String(localized: "premium.trends.title", defaultValue: "Long-range comparison"),
                detail: String(localized: "premium.trends.detail",
                               defaultValue: "Compare months and seasons, not just the last few weeks.")
            ),
            Feature(
                symbol: "sparkles",
                title: String(localized: "premium.models.title", defaultValue: "Better detection"),
                detail: String(localized: "premium.models.detail",
                               defaultValue: "Improved on-device models as they become available.")
            ),
            Feature(
                symbol: "square.and.arrow.up",
                title: String(localized: "premium.export.title", defaultValue: "Full exports"),
                detail: String(localized: "premium.export.detail",
                               defaultValue: "Take every night with you, in one file.")
            ),
            Feature(
                symbol: "lock.icloud",
                title: String(localized: "premium.backup.title", defaultValue: "Encrypted backup"),
                detail: String(localized: "premium.backup.detail",
                               defaultValue: "Your nights, encrypted, on your own iCloud.")
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                SomnaCard {
                    Label {
                        Text(String(localized: "premium.badge", defaultValue: "Coming later"))
                            .font(SomnaFont.cardTitle)
                            .foregroundStyle(SomnaColor.textPrimary)
                    } icon: {
                        Image(systemName: "hourglass")
                            .foregroundStyle(palette.accentSecondary)
                    }

                    Text(String(
                        localized: "premium.intro",
                        defaultValue: "None of this exists yet, and nothing here can be bought. It is a sketch of where Somna could go — tell me which of these you would actually use."
                    ))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
                }

                ForEach(features) { feature in
                    SomnaCard {
                        Label {
                            Text(feature.title)
                                .font(SomnaFont.cardTitle)
                                .foregroundStyle(SomnaColor.textPrimary)
                        } icon: {
                            Image(systemName: feature.symbol)
                                .foregroundStyle(palette.accentPrimary)
                        }

                        Text(feature.detail)
                            .font(SomnaFont.secondary)
                            .foregroundStyle(SomnaColor.textSecondary)
                    }
                }

                Text(String(
                    localized: "premium.freeForever",
                    defaultValue: "Recording, analysis, reports and deletion will stay free. Nothing that already works today will move behind a payment."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
            }
            .padding(SomnaSpacing.l)
        }
        .background(SomnaColor.backgroundPrimary)
        .accessibilityIdentifier("premium.root")
        .navigationTitle(Text(String(localized: "premium.title", defaultValue: "Somna Plus")))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack { PremiumView() }
        .environment(\.somna, .preview())
}
#endif
