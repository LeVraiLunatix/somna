import SwiftUI

/// Animation vocabulary.
///
/// Kept deliberately small. An app used at 3 a.m. by someone half awake should
/// move as little as possible, and every animation here has to justify itself by
/// explaining a change of state — never by decorating one.
enum SomnaMotion {

    /// Default for state changes: appearing cards, expanding groups.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Quick acknowledgements: toggles, selection.
    static let quick = Animation.easeOut(duration: 0.18)

    /// Reserved for the one moment that deserves weight — starting and ending a
    /// night session.
    static let emphasis = Animation.spring(response: 0.5, dampingFraction: 0.75)
}

/// Applies an animation unless the user asked the system to reduce motion.
///
/// A `ViewModifier` rather than a free function because `accessibilityReduceMotion`
/// only exists in the environment. Routing every animation through here means a
/// screen physically cannot forget the setting.
private struct SomnaAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Animates a change, honouring Reduce Motion automatically.
    ///
    /// Reduce Motion removes the animation, not the state change: the interface
    /// still updates, it simply arrives instead of travelling.
    func somnaAnimation<Value: Equatable>(
        _ animation: Animation = SomnaMotion.standard,
        value: Value
    ) -> some View {
        modifier(SomnaAnimationModifier(animation: animation, value: value))
    }
}
