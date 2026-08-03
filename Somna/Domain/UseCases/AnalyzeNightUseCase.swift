import Foundation
import OSLog

/// Runs the morning pass on a night and stores what it found.
///
/// The status transitions matter: a night moves to `analyzing` before the work
/// starts, so an app killed mid-analysis is recognisable at next launch instead
/// of appearing to be still waiting. A failure returns it to `awaitingAnalysis`
/// rather than `failed` — the audio is intact and can be tried again, and
/// `failed` would read as "this night is lost" for a night that is not.
struct AnalyzeNightUseCase: Sendable {

    let sessions: any NightSessionRepositing
    let analyser: any NightAnalyzing
    let settings: any SettingsStoring
    let notifications: any NotificationScheduling
    let clock: any Clocking

    @discardableResult
    func callAsFunction(
        sessionID: UUID,
        onProgress: @Sendable @escaping (AnalysisProgress) -> Void = { _ in }
    ) async throws -> NightSession {

        guard var session = try await sessions.session(id: sessionID) else {
            throw SomnaError.sessionNotFound(id: sessionID)
        }

        guard session.isAnalysable else {
            // Not an error: a three-minute session is a legitimate thing to have
            // recorded. It simply cannot support a report, and saying so is the
            // honest outcome rather than producing one anyway.
            session.status = .interrupted
            session.updatedAt = clock.now
            try await sessions.save(session)
            throw SomnaError.recordingTooShort(
                recorded: session.recordedDuration,
                minimum: AnalysisConstants.minimumAnalysableDuration
            )
        }

        let segments = try await sessions.segments(for: sessionID)

        session.status = .analyzing
        session.updatedAt = clock.now
        try await sessions.save(session)

        do {
            let outcome = try await analyser.analyse(
                session: session,
                segments: segments,
                settings: settings.load(),
                onProgress: onProgress
            )

            session.status = .completed
            session.statistics = outcome.statistics
            session.recordingQuality = outcome.quality
            session.calmnessScore = outcome.calmnessScore
            session.summaryStatements = outcome.summary
            session.estimatedSleepStart = outcome.sleepWindow.sleepStart
            session.estimatedWakeTime = outcome.sleepWindow.wakeTime
            session.analysisVersion = AnalysisConstants.currentVersion
            session.updatedAt = clock.now

            try await sessions.replaceEvents(outcome.events, for: sessionID)
            try await sessions.save(session)

            // The one place a "your report is ready" notification can honestly
            // be sent: a report has just been produced.
            if settings.load().morningSummaryEnabled {
                await notifications.notifyReportReady(sessionID: sessionID)
            }

            Log.analysis.info("Analysed \(Log.short(sessionID), privacy: .public): \(outcome.events.count, privacy: .public) event(s)")
            return session

        } catch {
            session.status = .awaitingAnalysis
            session.updatedAt = clock.now
            try? await sessions.save(session)

            Log.analysis.error("Analysis failed for \(Log.short(sessionID), privacy: .public); the recording is unchanged")
            throw error
        }
    }
}
