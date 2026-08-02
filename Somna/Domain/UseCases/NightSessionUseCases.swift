import Foundation
import OSLog

/// Starts a night.
///
/// The order matters and is the point of having a use case rather than doing
/// this in the store: the database row is written **before** the engine starts.
/// If the app dies between the two, launch recovery finds a session with no
/// audio and cleans it up. The reverse order would leave audio on disk that
/// nothing references — invisible storage growth, and a lost night.
struct StartNightSessionUseCase: Sendable {

    let sessions: any NightSessionRepositing
    let recorder: any AudioRecording
    let files: any NightFileStoring
    let settings: any SettingsStoring
    let clock: any Clocking

    func callAsFunction() async throws -> NightSession {
        let available = files.availableCapacity()
        guard available >= AudioConstants.minimumFreeSpaceToRecord else {
            throw SomnaError.insufficientStorage(
                requiredBytes: AudioConstants.minimumFreeSpaceToRecord,
                availableBytes: available
            )
        }

        let now = clock.now
        let session = NightSession(
            startDate: now,
            status: .recording,
            createdAt: now,
            updatedAt: now
        )

        try await sessions.save(session)

        do {
            try await recorder.start(sessionID: session.id, bitRate: settings.load().audioBitRate)
        } catch {
            // The engine never started, so there is nothing to recover. Removing
            // the row now keeps an empty night out of the user's history.
            try? await sessions.deleteSession(id: session.id)
            try? files.removeSessionDirectory(for: session.id)
            throw error
        }

        Log.audio.info("Night session started: \(Log.short(session.id), privacy: .public)")
        return session
    }
}

/// Ends a night and records what it produced.
struct StopNightSessionUseCase: Sendable {

    let sessions: any NightSessionRepositing
    let recorder: any AudioRecording
    let clock: any Clocking

    func callAsFunction(reason: StopReason) async throws -> NightSession {
        let outcome = try await recorder.stop(reason: reason)

        guard var session = try await sessions.session(id: outcome.sessionID) else {
            throw SomnaError.sessionNotFound(id: outcome.sessionID)
        }

        session.endDate = outcome.endDate
        session.recordedDuration = outcome.recordedDuration
        session.updatedAt = clock.now

        // Only a deliberate stop yields a night ready for analysis; anything else
        // is interrupted, which keeps the audio and lets the user decide.
        session.status = RecordingState.stopped(reason: reason).resultingSessionStatus

        // A night with too little audio is marked rather than analysed. Five
        // minutes cannot support any statement about a night, and producing a
        // report anyway would be exactly the false precision this app avoids.
        if !session.isAnalysable {
            session.status = .interrupted
        }

        try await sessions.save(session)

        for segment in outcome.segments {
            try await sessions.save(segment)
        }

        Log.audio.info("Night session stopped: \(Log.short(session.id), privacy: .public), \(outcome.segments.count, privacy: .public) segment(s), \(outcome.gaps.count, privacy: .public) gap(s)")
        return session
    }
}

/// Cleans up after a crash, at launch.
///
/// Two failure modes are repaired here, both of which are otherwise silent:
///
/// * A session row left in `recording` because the app died mid-night. It is
///   reconciled against the manifest on disk and marked `interrupted`, so the
///   night appears in history with the audio it actually captured instead of
///   looking like it is still running forever.
/// * Directories with no matching row, and `.part` files from a write that never
///   finished. They occupy space while being unreachable from any screen.
struct RecoverInterruptedSessionsUseCase: Sendable {

    let sessions: any NightSessionRepositing
    let files: any NightFileStoring
    let clock: any Clocking

    @discardableResult
    func callAsFunction() async throws -> [NightSession] {
        var recovered: [NightSession] = []

        for session in try await sessions.unfinishedSessions() where session.status == .recording {
            recovered.append(try await reconcile(session))
        }

        try await removeOrphans()
        return recovered
    }

    private func reconcile(_ session: NightSession) async throws -> NightSession {
        var updated = session

        // The manifest is the authority here: it was rewritten after every
        // segment, so it knows how much audio actually landed. The database row
        // only knows the night started.
        if let manifest = NightManifest.read(sessionID: session.id, using: files) {
            updated.recordedDuration = manifest.recordedDuration
            updated.endDate = manifest.endDate ?? manifest.segments.last?.endDate

            for segment in manifest.reconstructedSegments() {
                try? await sessions.save(segment)
            }
        }

        updated.status = .interrupted
        updated.updatedAt = clock.now
        try await sessions.save(updated)

        Log.storage.info("Recovered interrupted night \(Log.short(session.id), privacy: .public)")
        return updated
    }

    private func removeOrphans() async throws {
        let known = Set(try await sessions.sessions().map(\.id))

        for directory in files.orphanedSessionDirectories(knownSessionIDs: known) {
            try? FileManager.default.removeItem(at: directory)
            Log.storage.info("Removed an orphaned night directory")
        }

        // A `.part` file is a segment that was being written when the app died.
        // Its content is truncated, so analysing it would produce events from
        // audio that was never fully encoded.
        for id in known {
            for incomplete in files.incompleteSegmentFiles(for: id) {
                try? FileManager.default.removeItem(at: incomplete)
            }
        }
    }
}
