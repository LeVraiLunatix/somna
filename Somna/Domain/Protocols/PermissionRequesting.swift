import Foundation

/// Microphone authorisation, in domain terms.
///
/// `permanentlyDenied` is separated from `denied` because the two need different
/// interfaces: one can be resolved by a button in the app, the other only in iOS
/// Settings. Collapsing them produces the familiar dead end where a button
/// re-requests a permission iOS will never prompt for again.
enum MicrophonePermission: String, Sendable, Equatable {
    case undetermined
    case granted
    case denied
    case permanentlyDenied
}

enum NotificationPermission: String, Sendable, Equatable {
    case undetermined
    case granted
    case denied
    case provisional
}

protocol PermissionRequesting: Sendable {
    func microphonePermission() async -> MicrophonePermission
    func requestMicrophonePermission() async -> MicrophonePermission

    func notificationPermission() async -> NotificationPermission
    func requestNotificationPermission() async -> NotificationPermission

    /// Opens Somna's page in iOS Settings, the only route out of
    /// `permanentlyDenied`.
    @MainActor func openSystemSettings()
}

extension MicrophonePermission {
    /// Whether a session can start at all.
    var allowsRecording: Bool { self == .granted }

    /// Whether asking again would produce a system prompt. When `false`, the UI
    /// must send the user to Settings instead of offering a button that does
    /// nothing.
    var canPrompt: Bool { self == .undetermined }
}
