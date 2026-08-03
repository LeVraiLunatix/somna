import SwiftUI

/// The floating player.
///
/// One of the six surfaces where Liquid Glass earns its place: it sits above
/// scrolling content, it is the only thing on screen that is not the list, and
/// the material is what says so. `somnaGlass` handles Reduce Transparency, so
/// the choice degrades rather than breaks.
struct PlaybackPanel: View {

    @Environment(ClipPlayer.self) private var player

    var body: some View {
        if let item = player.current {
            VStack(spacing: SomnaSpacing.s) {
                header(item)

                if let failure = player.failure {
                    Text(failure.recoverySuggestion ?? "")
                        .font(SomnaFont.caption)
                        .foregroundStyle(SomnaColor.textSecondary)
                } else {
                    scrubber
                    transport
                }
            }
            .padding(SomnaSpacing.l)
            .somnaGlass(cornerRadius: SomnaRadius.large, interactive: true)
            .padding(.horizontal, SomnaSpacing.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .somnaAnimation(value: item.id)
            .accessibilityIdentifier("player.panel")
        }
    }

    private func header(_ item: PlaybackItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SomnaSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.event.title)
                    .font(SomnaFont.cardTitle)
                    .foregroundStyle(SomnaColor.textPrimary)

                Text(item.event.startDate.formatted(.dateTime.hour().minute()))
                    .font(SomnaFont.caption)
                    .foregroundStyle(SomnaColor.textSecondary)
            }

            Spacer(minLength: SomnaSpacing.s)

            Button {
                player.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(.title3))
                    .foregroundStyle(SomnaColor.textTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: SomnaSpacing.minimumTapTarget, height: SomnaSpacing.minimumTapTarget)
            .accessibilityLabel(Text(String(localized: "player.close", defaultValue: "Close player")))
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            MiniWaveform(
                samples: player.current?.event.waveformSamples ?? [],
                progress: player.progress
            )
            .frame(height: 30)

            HStack {
                Text(player.currentTime.formattedCompactDuration)
                Spacer()
                Text(player.duration.formattedCompactDuration)
            }
            .font(SomnaFont.caption)
            .monospacedDigit()
            .foregroundStyle(SomnaColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "player.progress",
            defaultValue: "Playback position"
        )))
        .accessibilityValue(Text(player.currentTime.formattedDuration()))
    }

    private var transport: some View {
        HStack(spacing: SomnaSpacing.l) {
            transportButton(
                "backward.end",
                label: String(localized: "player.previous", defaultValue: "Previous moment"),
                enabled: player.canPlayPrevious || player.currentTime > 2
            ) {
                player.playPrevious()
            }

            transportButton(
                "gobackward.5",
                label: String(localized: "player.back5", defaultValue: "Back 5 seconds")
            ) {
                player.skip(by: -ClipPlayer.skipInterval)
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SomnaColor.accentPrimary)
            }
            .buttonStyle(.plain)
            .frame(width: 52, height: 52)
            .accessibilityLabel(Text(player.isPlaying
                ? String(localized: "player.pause", defaultValue: "Pause")
                : String(localized: "player.play", defaultValue: "Play")))

            transportButton(
                "goforward.5",
                label: String(localized: "player.forward5", defaultValue: "Forward 5 seconds")
            ) {
                player.skip(by: ClipPlayer.skipInterval)
            }

            rateButton
        }
    }

    /// Slowing a clip down is what makes a faint sound identifiable, which is
    /// the only reason rates exist here — not for skimming.
    private var rateButton: some View {
        @Bindable var player = player

        return Menu {
            Picker(String(localized: "player.rate", defaultValue: "Speed"), selection: $player.rate) {
                ForEach(ClipPlayer.availableRates, id: \.self) { rate in
                    Text(verbatim: "\(rate.formatted())×").tag(rate)
                }
            }
        } label: {
            Text(verbatim: "\(player.rate.formatted())×")
                .font(SomnaFont.caption.monospacedDigit())
                .foregroundStyle(SomnaColor.textSecondary)
                .frame(width: SomnaSpacing.minimumTapTarget,
                       height: SomnaSpacing.minimumTapTarget)
        }
        .accessibilityLabel(Text(String(localized: "player.rate", defaultValue: "Speed")))
    }

    private func transportButton(
        _ symbol: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.title3))
                .foregroundStyle(enabled ? SomnaColor.textPrimary : SomnaColor.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .frame(width: SomnaSpacing.minimumTapTarget, height: SomnaSpacing.minimumTapTarget)
        .accessibilityLabel(Text(label))
    }
}

extension View {
    /// Overlays the player above a screen's content.
    func withPlaybackPanel() -> some View {
        overlay(alignment: .bottom) {
            PlaybackPanel()
                .padding(.bottom, SomnaSpacing.s)
        }
    }
}
