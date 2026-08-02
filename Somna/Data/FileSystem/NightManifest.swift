import Foundation
import OSLog

/// A night's own record of itself, written next to its audio.
///
/// Deliberately redundant with SwiftData. It costs a few kilobytes per night and
/// buys the one guarantee that matters to a beta tester: if the store is
/// corrupted, or a migration goes wrong, or the app is deleted and reinstalled
/// over restored files, the night is still reconstructible from disk.
///
/// Rewritten after **every segment** rather than at the end, because the
/// situations worth recovering from are precisely the ones where the end never
/// arrives.
struct NightManifest: Codable, Equatable, Sendable {

    /// Bumped when the shape changes, so a future build can tell an old manifest
    /// from a corrupt one rather than guessing.
    static let currentVersion = 1

    var version: Int = NightManifest.currentVersion
    let sessionID: UUID
    let startDate: Date
    /// `nil` while the night is still running — which is itself the signal that
    /// the session did not end cleanly.
    let endDate: Date?
    let recordedDuration: TimeInterval
    let segments: [ManifestSegment]
    let gaps: [RecordingGap]
    let stopReason: StopReason?

    /// Segment metadata, flattened.
    ///
    /// Not `AudioSegment` directly: the domain type may gain fields that make no
    /// sense on disk, and a manifest that fails to decode because the app grew a
    /// property would defeat the entire point of having one.
    struct ManifestSegment: Codable, Equatable, Sendable {
        let id: UUID
        let fileName: String
        let startDate: Date
        let endDate: Date
        let fileSize: Int64
    }

    init(
        sessionID: UUID,
        startDate: Date,
        endDate: Date?,
        recordedDuration: TimeInterval,
        segments: [AudioSegment],
        gaps: [RecordingGap],
        stopReason: StopReason?
    ) {
        self.sessionID = sessionID
        self.startDate = startDate
        self.endDate = endDate
        self.recordedDuration = recordedDuration
        self.gaps = gaps
        self.stopReason = stopReason
        self.segments = segments.map {
            ManifestSegment(
                id: $0.id,
                fileName: $0.fileName,
                startDate: $0.startDate,
                endDate: $0.endDate,
                fileSize: $0.fileSize
            )
        }
    }

    // MARK: - Disk

    static let fileName = "manifest.json"

    func write(using files: any NightFileStoring) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let url = files.sessionDirectory(for: sessionID).appending(path: Self.fileName)
        try files.writeAtomically(try encoder.encode(self), to: url)
    }

    static func read(sessionID: UUID, using files: any NightFileStoring) -> NightManifest? {
        let url = files.sessionDirectory(for: sessionID).appending(path: fileName)

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let manifest = try decoder.decode(NightManifest.self, from: data)
            guard manifest.version <= currentVersion else {
                // Written by a newer build. Refusing is safer than misreading it:
                // a half-understood manifest could produce a night with the wrong
                // duration or missing segments.
                Log.storage.error("Manifest version \(manifest.version, privacy: .public) is newer than this build understands")
                return nil
            }
            return manifest
        } catch {
            Log.storage.error("Manifest for \(Log.short(sessionID), privacy: .public) could not be decoded")
            return nil
        }
    }

    /// Rebuilds the domain session this manifest describes.
    ///
    /// A manifest with no `endDate` describes a night that never stopped
    /// cleanly, so the reconstruction is marked `interrupted` — which keeps the
    /// audio and lets the user decide, rather than `failed`, which reads as
    /// "your night is gone".
    func reconstructedSession(now: Date) -> NightSession {
        NightSession(
            id: sessionID,
            startDate: startDate,
            endDate: endDate ?? segments.last?.endDate,
            status: endDate == nil ? .interrupted : .awaitingAnalysis,
            recordedDuration: recordedDuration,
            createdAt: startDate,
            updatedAt: now
        )
    }

    func reconstructedSegments() -> [AudioSegment] {
        segments.map {
            AudioSegment(
                id: $0.id,
                sessionID: sessionID,
                fileName: $0.fileName,
                startDate: $0.startDate,
                endDate: $0.endDate,
                fileSize: $0.fileSize,
                processingState: .ready
            )
        }
    }
}
