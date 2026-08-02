import Foundation

/// The subsystems Somna logs under.
///
/// Categories are a closed set so Console filtering stays predictable and so no
/// ad-hoc category can appear with a name that leaks product information.
enum LogCategory: String, Sendable, CaseIterable {
    case app
    case audio
    case analysis
    case persistence
    case notifications
    case storage
    case privacy
    case ui
}
