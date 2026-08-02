import SwiftUI

/// The only place in Somna that applies Liquid Glass.
///
/// Two problems are solved by funnelling every glass surface through one
/// modifier:
///
/// 1. **Accessibility cannot be forgotten.** `Reduce Transparency` and
///    `Increased Contrast` are handled here, once. A screen written six months
///    from now inherits the behaviour instead of having to remember it.
/// 2. **Overuse becomes visible.** Glass is legitimate on a handful of floating
///    surfaces — the audio player, the start button, a few sheets. Counting call
///    sites of one modifier is a code review anyone can do; spotting scattered
///    `.glassEffect` calls is not.
///
/// The fallback is a solid surface, not a translucent material. Someone who
/// turned transparency off asked for opacity, and half-honouring that is worse
/// than ignoring it.
struct GlassSurface: ViewModifier {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let cornerRadius: CGFloat
    let isInteractive: Bool

    private var wantsSolidSurface: Bool {
        reduceTransparency || contrast == .increased
    }

    func body(content: Content) -> some View {
        if wantsSolidSurface {
            content
                .background(SomnaColor.surfaceElevated, in: shape)
                .overlay(shape.strokeBorder(SomnaColor.separator, lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glass: Glass {
        isInteractive ? .regular.interactive() : .regular
    }
}

extension View {

    /// Applies Somna's glass treatment, degrading to a solid surface when the
    /// user has reduced transparency or raised contrast.
    ///
    /// - Parameter interactive: pass `true` only for surfaces the user actually
    ///   presses, so the material reacts to touch. Decorative surfaces stay
    ///   still: motion the user did not cause is noise.
    func somnaGlass(
        cornerRadius: CGFloat = SomnaRadius.large,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, isInteractive: interactive))
    }
}
