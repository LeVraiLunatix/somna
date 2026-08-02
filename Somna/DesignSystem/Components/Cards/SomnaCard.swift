import SwiftUI

/// The standard container for grouped content.
///
/// Solid rather than glass by default. Most of what Somna shows is data to be
/// read, and reading is what translucency costs most.
struct SomnaCard<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SomnaSpacing.m) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SomnaSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: SomnaRadius.medium, style: .continuous)
                .fill(SomnaColor.surface)
        )
    }
}

/// A labelled row with a trailing value and a status colour.
///
/// The colour is never the only signal: `state` also drives the SF Symbol, so
/// the row still reads correctly under `Differentiate Without Color` and for
/// anyone who cannot distinguish the hues.
struct StatusRow: View {

    enum State: Sendable {
        case ok
        case attention
        case problem
        case neutral

        var symbolName: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .attention: "exclamationmark.triangle.fill"
            case .problem: "xmark.circle.fill"
            case .neutral: "circle.dashed"
            }
        }

        var tint: Color {
            switch self {
            case .ok: SomnaColor.success
            case .attention: SomnaColor.warning
            case .problem: SomnaColor.error
            case .neutral: SomnaColor.textTertiary
            }
        }
    }

    let label: String
    let value: String
    let state: State

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SomnaSpacing.m) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .accessibilityHidden(true)

            Text(label)
                .font(SomnaFont.body)
                .foregroundStyle(SomnaColor.textPrimary)

            Spacer(minLength: SomnaSpacing.s)

            Text(value)
                .font(SomnaFont.timestamp)
                .foregroundStyle(SomnaColor.textSecondary)
                // Long values wrap instead of truncating: at AX5 a truncated
                // status is indistinguishable from a missing one.
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
