import Foundation

/// Everything the app needs from storage, expressed in domain terms.
///
/// The features depend on this, never on SwiftData. That indirection is what
/// makes the SwiftData risk identified in Phase 1 (R5) a replaceable
/// implementation detail rather than a rewrite: if the persistent store has to
/// change, only `Data/` moves.
///
/// All methods are `async` because the real implementation is a `@ModelActor`
/// running off the main thread.
protocol NightSessionRepositing: Sendable {

    func sessions(limit: Int?, offset: Int) async throws -> [NightSession]
    func session(id: UUID) async throws -> NightSession?
    func mostRecentSession() async throws -> NightSession?

    /// Sessions that stopped without finishing, so the app can offer to analyse
    /// what was captured instead of silently discarding it.
    func unfinishedSessions() async throws -> [NightSession]

    func save(_ session: NightSession) async throws
    func deleteSession(id: UUID) async throws
    func deleteAllSessions() async throws

    func events(for sessionID: UUID) async throws -> [NightEvent]
    func replaceEvents(_ events: [NightEvent], for sessionID: UUID) async throws
    func updateEvent(_ event: NightEvent) async throws

    func segments(for sessionID: UUID) async throws -> [AudioSegment]
    func save(_ segment: AudioSegment) async throws

    func latestCalibration() async throws -> CalibrationProfile?
    func save(_ calibration: CalibrationProfile) async throws
}

extension NightSessionRepositing {
    func sessions() async throws -> [NightSession] {
        try await sessions(limit: nil, offset: 0)
    }
}
