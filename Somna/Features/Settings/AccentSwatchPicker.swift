import SwiftUI

/// The four accents, all four visible at once.
///
/// This used to be a `Picker` whose rows carried
/// `Image(systemName: "circle.fill").foregroundStyle(palette.swatch)`. Inside a
/// menu, SwiftUI renders a row's icon as a **template** image and tints it with
/// the menu's tint, which discards `foregroundStyle` entirely. All four swatches
/// therefore came out the same colour — the colour already selected — so the one
/// control in the app whose whole job is previewing a colour previewed nothing,
/// and did it convincingly enough to look deliberate.
///
/// Drawn as ordinary shapes outside a menu, the fills survive. Showing all four
/// at once is also simply the better control: picking a colour from a list of
/// names you open one at a time is picking blind.
struct AccentSwatchPicker: View {

    @Binding var selection: ThemePalette
    let title: (ThemePalette) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: SomnaSpacing.m) {
            Text(String(localized: "settings.palette", defaultValue: "Accent"))
                .foregroundStyle(SomnaColor.textPrimary)

            // A row, not a LabeledContent: four 44pt targets beside a label
            // clip the moment the text size goes up, and this screen is read at
            // whatever size the user already needs.
            HStack(spacing: SomnaSpacing.m) {
                ForEach(ThemePalette.allCases) { palette in
                    swatch(palette)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.accent")
    }

    private func swatch(_ palette: ThemePalette) -> some View {
        Button {
            selection = palette
        } label: {
            Circle()
                .fill(palette.swatch)
                .frame(width: 28, height: 28)
                .overlay {
                    // Selection never rests on colour alone. Four saturated
                    // circles look alike to a colour-blind eye, and Ink hardly
                    // reads as a colour at all.
                    if selection == palette {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SomnaColor.backgroundPrimary)
                    }
                }
                .overlay {
                    Circle().strokeBorder(
                        SomnaColor.textPrimary.opacity(selection == palette ? 0.85 : 0.18),
                        lineWidth: selection == palette ? 2 : 1
                    )
                }
                .frame(width: SomnaSpacing.minimumTapTarget,
                       height: SomnaSpacing.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(palette))
        .accessibilityAddTraits(selection == palette ? [.isButton, .isSelected] : .isButton)
    }
}
