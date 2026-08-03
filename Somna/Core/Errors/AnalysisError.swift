import Foundation

/// Failures during the morning pass.
enum AnalysisError: Error, Equatable, Sendable {
    /// The system sound classifier could not be created or opened.
    case classifierUnavailable
    /// Every segment of the night failed to read.
    case noReadableAudio
    /// The user or the system stopped the analysis before it finished.
    case cancelled
}

extension AnalysisError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .classifierUnavailable:
            String(localized: "analysis.classifier.title",
                   defaultValue: "Somna could not analyse this night")
        case .noReadableAudio:
            String(localized: "analysis.noAudio.title",
                   defaultValue: "The audio for this night could not be read")
        case .cancelled:
            String(localized: "analysis.cancelled.title",
                   defaultValue: "Analysis was stopped")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .classifierUnavailable:
            String(localized: "analysis.classifier.suggestion",
                   defaultValue: "Your recording is safe. Try analysing it again from the night's page.")
        case .noReadableAudio:
            String(localized: "analysis.noAudio.suggestion",
                   defaultValue: "The files may have been removed. Nothing else on the device is affected.")
        case .cancelled:
            String(localized: "analysis.cancelled.suggestion",
                   defaultValue: "You can start it again whenever you like.")
        }
    }
}
