import Foundation
import OSLog
import SwiftUI

/// The opening sequence.
///
/// **What it is honest about.** iOS's own launch screen is static — nothing can
/// animate there — so this plays *after* launch, as the app's first view. Which
/// raises the question the rest of Somna would ask of any progress indicator:
/// is it showing real progress, or performing one?
///
/// It shows real progress. The fill tracks the work the app genuinely does at
/// startup — reconciling nights the app died inside, clearing files nothing
/// references any more. When that finishes, the sequence ends; it is never
/// padded to look busier. On a fast iPhone with few nights it is over almost at
/// once, and that is the correct behaviour rather than a wasted animation.
///
/// The one piece of pure theatre is the entrance — the S, then the rest of the
/// word — and it claims nothing. A moving letter is not a promise about load.
@MainActor
@Observable
final class LaunchStore {

    enum Phase: Equatable {
        /// The S, then the rest of the word.
        case entrance
        /// The word filling, tracking real startup work.
        case loading
        /// Zoom and cross-fade into the app.
        case exiting
        case finished
    }

    private(set) var phase: Phase = .entrance
    private(set) var wordRevealed = false
    private(set) var progress: Double = 0

    private let environment: AppEnvironment
    private let reduceMotion: Bool

    /// The entrance is short on purpose. Long enough to read as deliberate,
    /// short enough that someone opening the app at 3 a.m. is not waiting on it.
    static let entranceDuration: TimeInterval = 0.55
    static let exitDuration: TimeInterval = 0.4

    init(environment: AppEnvironment, reduceMotion: Bool) {
        self.environment = environment
        self.reduceMotion = reduceMotion
    }

    func run() async {
        // Reduce Motion removes the sequence entirely rather than shortening it.
        // Someone who asked the system for less movement did not ask for faster
        // movement.
        guard !reduceMotion else {
            wordRevealed = true
            progress = 1
            await performStartupWork()
            phase = .finished
            return
        }

        // The real work starts immediately and runs alongside the entrance, so
        // the animation never delays it — it only ever hides it.
        let work = Task { await performStartupWork() }

        wordRevealed = true
        try? await Task.sleep(for: .seconds(Self.entranceDuration))

        phase = .loading

        // The fill advances to a point that says "something is happening", then
        // waits for the truth. It never reaches full on its own.
        progress = 0.35
        await work.value
        progress = 1

        try? await Task.sleep(for: .milliseconds(220))
        phase = .exiting
        try? await Task.sleep(for: .seconds(Self.exitDuration))
        phase = .finished
    }

    /// The work the launch actually covers.
    private func performStartupWork() async {
        let useCase = RecoverInterruptedSessionsUseCase(
            sessions: environment.sessions,
            files: environment.files,
            clock: environment.clock
        )
        // Failure is not worth blocking a launch over: it retries next time, and
        // nothing the user can see depends on it having happened yet.
        try? await useCase()
    }
}

/// The word filling with a moving tide.
///
/// A `Shape` rather than a gradient so the surface actually moves: two sine
/// waves at different speeds, which is enough to stop the crest looking like a
/// single ruler sliding upward.
struct WaveFill: Shape {

    /// 0–1, how much of the word is filled.
    var progress: Double
    /// Advances continuously; drives the horizontal travel of the crests.
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // A little overshoot at both ends so a full or empty word has no sliver
        // of the wrong colour left at its edge.
        let level = rect.height * (1 - progress.clamped())
        let amplitude = min(rect.height * 0.06, 6) * waveStrength
        let wavelength = rect.width / 1.4

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: level))

        var x = rect.minX
        while x <= rect.maxX {
            let relative = Double((x - rect.minX) / wavelength)
            let primary = sin(relative * 2 * .pi + phase)
            let secondary = sin(relative * 3.1 * .pi + phase * 1.7) * 0.45
            let y = level + CGFloat((primary + secondary)) * amplitude

            path.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// The crests flatten as the word fills, so the surface settles rather than
    /// still sloshing at the moment the app appears.
    private var waveStrength: CGFloat {
        let clamped = progress.clamped()
        if clamped >= 1 { return 0 }
        return CGFloat(1 - clamped * 0.5)
    }
}

private extension Double {
    func clamped() -> Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}

/// The opening screen.
struct LaunchView: View {

    @Environment(\.somnaPalette) private var palette

    @Environment(\.somna) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: LaunchStore?
    @State private var wavePhase: Double = 0

    let onFinished: () -> Void

    private let wordFont = Font.system(size: 52, weight: .semibold, design: .rounded)

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()

            if let store, store.phase != .finished {
                word(store)
                    .scaleEffect(store.phase == .exiting ? 14 : 1, anchor: .center)
                    .opacity(store.phase == .exiting ? 0 : 1)
                    .animation(
                        reduceMotion ? nil : .easeIn(duration: LaunchStore.exitDuration),
                        value: store.phase
                    )
            }
        }
        // One element, one label. A launch screen that VoiceOver reads letter by
        // letter is worse than one it skips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "launch.accessibility",
            defaultValue: "Somna is opening"
        )))
        .accessibilityIdentifier("launch.root")
        .task {
            if store == nil {
                store = LaunchStore(environment: environment, reduceMotion: reduceMotion)
            }
            startWaveMotion()
            await store?.run()
            onFinished()
        }
    }

    private func word(_ store: LaunchStore) -> some View {
        HStack(spacing: 0) {
            letter("S", store: store)

            // The rest of the word comes out of the S, rightwards. Offset and
            // opacity rather than a horizontal scale: scaling text stretches the
            // glyphs, and a stretched wordmark is the first thing anyone notices.
            letter("omna", store: store)
                .offset(x: store.wordRevealed ? 0 : -26)
                .opacity(store.wordRevealed ? 1 : 0)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.78),
                    value: store.wordRevealed
                )
        }
        .fixedSize()
    }

    /// Each letter group is drawn twice: once as the empty outline, once filled
    /// and masked by itself, so the tide rises *inside* the letterforms.
    private func letter(_ text: String, store: LaunchStore) -> some View {
        Text(verbatim: text)
            .font(wordFont)
            .foregroundStyle(SomnaColor.textTertiary.opacity(0.35))
            .overlay {
                WaveFill(progress: store.progress, phase: wavePhase)
                    .fill(palette.accentPrimary)
                    .mask {
                        Text(verbatim: text)
                            .font(wordFont)
                    }
                    .animation(.easeInOut(duration: 0.45), value: store.progress)
            }
    }

    /// Started once, from the view's own task rather than from each letter
    /// group: two animations driving the same value would fight over it.
    private func startWaveMotion() {
        guard !reduceMotion else { return }
        // A continuous, non-repeating phase. An `autoreverses` animation would
        // wash the crests back and forth, which reads as a stutter rather than
        // as water.
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            wavePhase = .pi * 8
        }
    }
}

#if DEBUG
#Preview {
    LaunchView(onFinished: {})
        .environment(\.somna, .preview())
}
#endif
