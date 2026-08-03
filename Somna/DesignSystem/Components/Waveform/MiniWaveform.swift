import SwiftUI

/// The envelope of a clip, drawn as bars.
///
/// Its job is recognition, not measurement: a cough looks like a spike, snoring
/// like a swell, a door like a single hard edge. Someone scanning a timeline can
/// tell those apart before reading a word, which is why every event carries one.
///
/// It is never the only signal — the label always says what the event is — so
/// nothing is lost when it is empty or when the viewer cannot see it.
struct MiniWaveform: View {

    let samples: [Float]
    /// Fraction already played, 0–1. Bars behind it are tinted.
    var progress: Double = 0
    /// `nil` follows the user's palette. A default parameter cannot read the
    /// environment, so the choice is expressed as absence rather than as a
    /// hard-coded colour that would ignore the setting.
    var tint: Color?

    @Environment(\.somnaPalette) private var palette

    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, Int(geometry.size.width / (barWidth + spacing)))
            let bars = resampled(to: count)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                    let played = Double(index) / Double(max(1, bars.count - 1)) <= progress

                    Capsule()
                        .fill(played ? resolvedTint : resolvedTint.opacity(0.28))
                        .frame(
                            width: barWidth,
                            // A floor of two points: a silent stretch should read
                            // as a quiet line, not as a gap in the drawing.
                            height: max(2, CGFloat(value) * geometry.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private var resolvedTint: Color { tint ?? palette.accentPrimary }

    /// Fits the stored envelope to the bars that actually fit on screen.
    ///
    /// Peak per bucket rather than mean, for the same reason the envelope was
    /// captured that way: a mean turns a cough into a flat line.
    private func resampled(to count: Int) -> [Float] {
        guard !samples.isEmpty else { return Array(repeating: 0.06, count: count) }
        guard samples.count > count else { return samples }

        let bucket = Double(samples.count) / Double(count)
        return (0..<count).map { index in
            let start = Int(Double(index) * bucket)
            let end = min(samples.count, Int(Double(index + 1) * bucket))
            guard start < end else { return samples[min(start, samples.count - 1)] }
            return samples[start..<end].max() ?? 0
        }
    }
}

/// The calmness score, shown as a ring.
///
/// The caveat is part of the component, not left to whichever screen uses it.
/// A number this prominent will be read as a verdict unless the words next to it
/// say otherwise, and those words must not be forgettable by a future caller.
struct CalmnessRing: View {

    @Environment(\.somnaPalette) private var palette

    let score: Int
    var showsCaption = true

    /// The ring grows with the text inside it. A fixed 120-point circle holding
    /// a Dynamic Type number clips it at the larger sizes — precisely where the
    /// number most needs to be readable.
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 120

    private var band: CalmnessScoreCalculator.Band {
        CalmnessScoreCalculator.Band(score: score)
    }

    var body: some View {
        VStack(spacing: SomnaSpacing.s) {
            ZStack {
                Circle()
                    .stroke(SomnaColor.separator, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: Double(score) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(SomnaColor.textPrimary)
                    Text(bandTitle)
                        .font(SomnaFont.caption)
                        .foregroundStyle(SomnaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: diameter, height: diameter)

            if showsCaption {
                Text(String(
                    localized: "report.calmness.caption",
                    defaultValue: "How quiet the recording was. Not a measure of your sleep."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
                .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            localized: "report.calmness.accessibility",
            defaultValue: "Calmness \(score) out of 100, \(bandTitle). This reflects how quiet the recording was, not the quality of your sleep."
        )))
    }

    private var bandTitle: String {
        switch band {
        case .veryCalm: String(localized: "report.band.veryCalm", defaultValue: "Very quiet")
        case .calm: String(localized: "report.band.calm", defaultValue: "Quiet")
        case .someActivity: String(localized: "report.band.someActivity", defaultValue: "Some activity")
        case .restless: String(localized: "report.band.restless", defaultValue: "Busy")
        }
    }

    private var tint: Color {
        switch band {
        case .veryCalm, .calm: palette.accentPrimary
        case .someActivity: SomnaColor.warning
        case .restless: SomnaColor.error
        }
    }
}
