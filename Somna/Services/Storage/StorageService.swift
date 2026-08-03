import Foundation
import OSLog

/// What Somna is actually taking up.
struct StorageBreakdown: Equatable, Sendable {
    var nightCount: Int
    var rawAudioBytes: Int64
    var clipBytes: Int64
    var availableBytes: Int64

    var totalBytes: Int64 { rawAudioBytes + clipBytes }

    static let empty = StorageBreakdown(
        nightCount: 0, rawAudioBytes: 0, clipBytes: 0, availableBytes: 0
    )
}

/// What a retention pass removed.
struct RetentionResult: Equatable, Sendable {
    var purgedNights: Int
    var freedBytes: Int64

    static let none = RetentionResult(purgedNights: 0, freedBytes: 0)
}

protocol StorageManaging: Sendable {
    func breakdown() async throws -> StorageBreakdown
    /// Deletes raw audio past the retention window, keeping the clips.
    func applyRetention(_ policy: AudioRetentionPolicy, now: Date) async throws -> RetentionResult
    /// Removes every recording and every night. Irreversible.
    func eraseEverything() async throws
    /// Removes raw audio for every night, keeping reports and clips.
    func eraseRawAudio() async throws -> RetentionResult
}

/// Storage accounting and deletion.
///
/// **Deletion order is the whole design.** Files go first, the database second.
/// The reverse would leave audio that nothing references — space consumed,
/// unreachable from every screen, and impossible for a user to find or remove.
/// A failure halfway through this order leaves orphans that launch recovery
/// cleans up; a failure halfway through the reverse order leaves nothing that
/// could ever find them.
struct StorageService: StorageManaging {

    let sessions: any NightSessionRepositing
    let files: any NightFileStoring

    func breakdown() async throws -> StorageBreakdown {
        let nights = try await sessions.sessions()

        var raw: Int64 = 0
        var clips: Int64 = 0

        for night in nights {
            let segments = try await sessions.segments(for: night.id)
            raw += segments.filter { $0.retentionState == .present }.reduce(0) { $0 + $1.fileSize }

            // Clips are measured from disk rather than summed from the database:
            // they are written by the analysis pass and their sizes are not
            // stored, and a figure that disagrees with iOS Settings is worse
            // than no figure.
            clips += directorySize(files.clipsDirectory(for: night.id))
        }

        return StorageBreakdown(
            nightCount: nights.count,
            rawAudioBytes: raw,
            clipBytes: clips,
            availableBytes: files.availableCapacity()
        )
    }

    func applyRetention(_ policy: AudioRetentionPolicy, now: Date) async throws -> RetentionResult {
        guard policy != .keepAll else { return .none }

        var result = RetentionResult.none

        for night in try await sessions.sessions() {
            let reference = night.endDate ?? night.startDate
            guard policy.shouldPurgeRawAudio(recordedAt: reference, now: now) else { continue }

            // Only nights that have been analysed are purged. Discarding the raw
            // audio of a night nobody has looked at yet would destroy the only
            // copy of something the user has not seen.
            guard night.status == .completed else { continue }

            let freed = try await purgeRawAudio(for: night.id)
            if freed > 0 {
                result.purgedNights += 1
                result.freedBytes += freed
            }
        }

        if result.purgedNights > 0 {
            Log.storage.info("Retention freed \(result.freedBytes, privacy: .public) bytes across \(result.purgedNights, privacy: .public) night(s)")
        }
        return result
    }

    func eraseRawAudio() async throws -> RetentionResult {
        var result = RetentionResult.none

        for night in try await sessions.sessions() {
            let freed = try await purgeRawAudio(for: night.id)
            if freed > 0 {
                result.purgedNights += 1
                result.freedBytes += freed
            }
        }
        return result
    }

    func eraseEverything() async throws {
        // Files first. See the type's documentation.
        try files.removeAllNights()
        try await sessions.deleteAllSessions()
        Log.privacy.info("All recordings and nights erased at the user's request")
    }

    // MARK: - Helpers

    /// Deletes the segment files of one night and marks its rows purged.
    ///
    /// The clips survive: they are what every timeline row is adossed to, and
    /// losing them would turn a checkable report into an unverifiable one.
    private func purgeRawAudio(for sessionID: UUID) async throws -> Int64 {
        let segments = try await sessions.segments(for: sessionID)
        var freed: Int64 = 0

        for segment in segments where segment.retentionState == .present {
            let url = files.segmentURL(for: sessionID, fileName: segment.fileName)
            let size = files.size(of: url)

            try? FileManager.default.removeItem(at: url)

            var updated = segment
            updated.retentionState = .purged
            try await sessions.save(updated)

            freed += size
        }
        return freed
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += files.size(of: url)
        }
        return total
    }
}
