import Charts
import SwiftUI

/// Backs the trends screen.
@MainActor
@Observable
final class TrendsStore {

    /// Below this, there is no trend — only a few nights next to each other.
    ///
    /// Drawing a line through two points and calling it a direction is the most
    /// common way a wellness app misleads. Somna refuses, and says why.
    static let minimumNights = 5

    /// How far back the charts look. Long enough to show a pattern, short enough
    /// that a change made three months ago does not still dominate the picture.
    static let window = 30

    struct Point: Identifiable, Equatable, Sendable {
        let id: UUID
        let date: Date
        let value: Double
    }

    enum LoadState: Equatable {
        case loading
        case notEnoughData(have: Int, need: Int)
        case ready
        case failed(SomnaError)
    }

    private(set) var state: LoadState = .loading
    private(set) var nights: [NightSession] = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        state = .loading
        do {
            // Only analysed nights: an interrupted one has partial numbers, and
            // charting them next to complete nights would show a dip that is
            // about the recording, not about the night.
            let all = try await environment.sessions.sessions()
            nights = all
                .filter { $0.status == .completed && $0.statistics != nil }
                .prefix(Self.window)
                .sorted { $0.startDate < $1.startDate }

            state = nights.count >= Self.minimumNights
                ? .ready
                : .notEnoughData(have: nights.count, need: Self.minimumNights)
        } catch let error as SomnaError {
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    // MARK: - Series

    var recordedDuration: [Point] {
        points { $0.recordedDuration / 3600 }
    }

    var calmness: [Point] {
        nights.compactMap { night in
            night.calmnessScore.map {
                Point(id: night.id, date: night.startDate, value: Double($0))
            }
        }
    }

    var snoringDuration: [Point] {
        points { ($0.statistics?.snoringDuration ?? 0) / 60 }
    }

    var coughCount: [Point] {
        points { Double($0.statistics?.coughCount ?? 0) }
    }

    var coverage: [Point] {
        points { ($0.captureCoverage ?? 1) * 100 }
    }

    private func points(_ value: (NightSession) -> Double) -> [Point] {
        nights.map { Point(id: $0.id, date: $0.startDate, value: value($0)) }
    }

    /// Averages, stated as averages rather than as findings.
    func average(_ points: [Point]) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
}

/// Simple, honest trends.
struct TrendsView: View {

    @Environment(\.somna) private var environment
    @State private var store: TrendsStore?

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("trends.root")
        .navigationTitle(Text(String(localized: "trends.title", defaultValue: "Trends")))
        .task {
            if store == nil { store = TrendsStore(environment: environment) }
            await store?.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(message: String(localized: "trends.loading", defaultValue: "Loading…"))

        case .failed(let error):
            ErrorStateView(error: error) { Task { await store?.load() } }

        case .notEnoughData(let have, let need):
            notEnoughData(have: have, need: need)

        case .ready:
            if let store {
                ScrollView {
                    VStack(alignment: .leading, spacing: SomnaSpacing.l) {
                        chart(
                            store: store,
                            points: store.calmness,
                            title: String(localized: "trends.calmness.title",
                                          defaultValue: "How quiet your nights were"),
                            explanation: String(
                                localized: "trends.calmness.explanation",
                                defaultValue: "The calmness score of each night, 0 to 100. It reflects how quiet the recording was, not how well you slept."
                            ),
                            unit: ""
                        )

                        chart(
                            store: store,
                            points: store.recordedDuration,
                            title: String(localized: "trends.duration.title",
                                          defaultValue: "How long you recorded"),
                            explanation: String(
                                localized: "trends.duration.explanation",
                                defaultValue: "Hours of audio captured each night. This is recording time, not sleep time — Somna cannot tell when you fell asleep."
                            ),
                            unit: String(localized: "trends.unit.hours", defaultValue: "h")
                        )

                        chart(
                            store: store,
                            points: store.snoringDuration,
                            title: String(localized: "trends.snoring.title",
                                          defaultValue: "Snoring detected"),
                            explanation: String(
                                localized: "trends.snoring.explanation",
                                defaultValue: "Minutes of snoring detected each night. If you share a room, Somna cannot tell whose it was."
                            ),
                            unit: String(localized: "trends.unit.minutes", defaultValue: "min")
                        )

                        chart(
                            store: store,
                            points: store.coughCount,
                            title: String(localized: "trends.coughs.title",
                                          defaultValue: "Coughs detected"),
                            explanation: String(
                                localized: "trends.coughs.explanation",
                                defaultValue: "How many coughs were detected each night. A cough can be missed, and other sounds can be mistaken for one."
                            ),
                            unit: ""
                        )

                        chart(
                            store: store,
                            points: store.coverage,
                            title: String(localized: "trends.coverage.title",
                                          defaultValue: "How much was actually captured"),
                            explanation: String(
                                localized: "trends.coverage.explanation",
                                defaultValue: "The share of each session Somna managed to record. A dip here means interruptions, and makes that night's other numbers less reliable."
                            ),
                            unit: "%"
                        )
                    }
                    .padding(SomnaSpacing.l)
                }
            }
        }
    }

    /// Refusing to draw a trend is itself the honest answer.
    private func notEnoughData(have: Int, need: Int) -> some View {
        VStack(spacing: SomnaSpacing.m) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(SomnaColor.textTertiary)
                .accessibilityHidden(true)

            Text(String(localized: "trends.empty.title", defaultValue: "Not enough nights yet"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            Text(String(
                localized: "trends.empty.body",
                defaultValue: "Somna has \(have) analysed nights and needs \(need) before showing trends. A line through two points is not a trend, and drawing one would say more than the data can."
            ))
            .font(SomnaFont.secondary)
            .foregroundStyle(SomnaColor.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(SomnaSpacing.xl)
    }

    private func chart(
        store: TrendsStore,
        points: [TrendsStore.Point],
        title: String,
        explanation: String,
        unit: String
    ) -> some View {
        SomnaCard {
            Text(title)
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            if points.isEmpty {
                Text(String(localized: "trends.noData",
                            defaultValue: "Nothing of this kind was detected in these nights."))
                    .font(SomnaFont.secondary)
                    .foregroundStyle(SomnaColor.textSecondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(SomnaColor.accentPrimary)
                        .interpolationMethod(.monotone)

                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(SomnaColor.accentPrimary)
                        .symbolSize(24)

                    // The average is drawn rather than only stated, so a single
                    // unusual night is visibly an outlier instead of looking
                    // like a change.
                    RuleMark(y: .value("Average", store.average(points)))
                        .foregroundStyle(SomnaColor.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 140)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                // Every chart is readable without seeing it: VoiceOver reads the
                // series rather than announcing "chart".
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(String(
                    localized: "trends.accessibility.summary",
                    defaultValue: "Average \(store.average(points).formatted(.number.precision(.fractionLength(1)))) \(unit) over \(points.count) nights."
                )))

                Text(String(
                    localized: "trends.average",
                    defaultValue: "Average: \(store.average(points).formatted(.number.precision(.fractionLength(1)))) \(unit)"
                ))
                .font(SomnaFont.caption.monospacedDigit())
                .foregroundStyle(SomnaColor.textSecondary)
            }

            // Every chart explains what it is. A chart nobody can interpret is
            // decoration, and decoration about someone's health is worse than none.
            Text(explanation)
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.textTertiary)
        }
    }
}
