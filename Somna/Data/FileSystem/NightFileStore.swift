import Foundation
import OSLog

/// Where a night's files live and how they are written.
///
/// Layout:
/// ```
/// Application Support/Somna/
///   Nights/<sessionUUID>/
///     segments/   seg-000.m4a  seg-000.features.jsonl
///     clips/      evt-<uuid>.m4a
///     manifest.json
/// ```
///
/// `manifest.json` is deliberately redundant with SwiftData. It costs a few
/// kilobytes per night and means a corrupted store, or a migration that goes
/// wrong, does not destroy a beta tester's recordings — the night can be rebuilt
/// from disk. Cheapest insurance in the project.
protocol NightFileStoring: Sendable {
    func sessionDirectory(for sessionID: UUID) -> URL
    func segmentsDirectory(for sessionID: UUID) -> URL
    func clipsDirectory(for sessionID: UUID) -> URL

    func prepareDirectories(for sessionID: UUID) throws
    func removeSessionDirectory(for sessionID: UUID) throws
    func removeAllNights() throws

    func segmentURL(for sessionID: UUID, fileName: String) -> URL
    func clipURL(for sessionID: UUID, fileName: String) -> URL

    func writeAtomically(_ data: Data, to url: URL) throws
    func size(of url: URL) -> Int64
    func totalSize(for sessionID: UUID) -> Int64
    func availableCapacity() -> Int64

    /// Session directories on disk with no matching row in the database, and
    /// half-written `.part` files left by a crash.
    func orphanedSessionDirectories(knownSessionIDs: Set<UUID>) -> [URL]
    func incompleteSegmentFiles(for sessionID: UUID) -> [URL]
}

struct NightFileStore: NightFileStoring {

    private let root: URL

    /// - Parameter root: overridden in tests so no suite writes into the real
    ///   container.
    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = URL.applicationSupportDirectory
            self.root = base.appending(path: "Somna", directoryHint: .isDirectory)
        }
    }

    // MARK: - Locations

    private var nightsDirectory: URL {
        root.appending(path: "Nights", directoryHint: .isDirectory)
    }

    func sessionDirectory(for sessionID: UUID) -> URL {
        nightsDirectory.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
    }

    func segmentsDirectory(for sessionID: UUID) -> URL {
        sessionDirectory(for: sessionID).appending(path: "segments", directoryHint: .isDirectory)
    }

    func clipsDirectory(for sessionID: UUID) -> URL {
        sessionDirectory(for: sessionID).appending(path: "clips", directoryHint: .isDirectory)
    }

    func segmentURL(for sessionID: UUID, fileName: String) -> URL {
        segmentsDirectory(for: sessionID).appending(path: fileName)
    }

    func clipURL(for sessionID: UUID, fileName: String) -> URL {
        clipsDirectory(for: sessionID).appending(path: fileName)
    }

    // MARK: - Lifecycle

    func prepareDirectories(for sessionID: UUID) throws {
        for directory in [segmentsDirectory(for: sessionID), clipsDirectory(for: sessionID)] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    // Recording must continue while the screen is locked, which
                    // `.complete` would prevent, but files stay encrypted at rest
                    // once closed.
                    .protectionKey: FileProtectionType.completeUnlessOpen
                ]
            )
        }
        try excludeFromBackup(sessionDirectory(for: sessionID))
    }

    func removeSessionDirectory(for sessionID: UUID) throws {
        let directory = sessionDirectory(for: sessionID)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func removeAllNights() throws {
        guard FileManager.default.fileExists(atPath: nightsDirectory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: nightsDirectory)
    }

    // MARK: - Writing

    /// Writes to a sibling temporary file and renames.
    ///
    /// A direct write interrupted by a crash or a battery cut leaves a truncated
    /// file that looks valid. The rename is atomic, so a reader sees either the
    /// previous state or the complete new one, never a half of either.
    func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appending(
            path: url.lastPathComponent + "." + AudioConstants.inProgressExtension
        )

        try data.write(to: temporary, options: [.atomic, .completeFileProtectionUnlessOpen])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    // MARK: - Measuring

    func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    func totalSize(for sessionID: UUID) -> Int64 {
        directorySize(sessionDirectory(for: sessionID))
    }

    func availableCapacity() -> Int64 {
        // `importantUsage` is the figure that reflects space iOS would free by
        // evicting purgeable data — the number that actually predicts whether a
        // long write will succeed.
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Recovery

    func orphanedSessionDirectories(knownSessionIDs: Set<UUID>) -> [URL] {
        contents(of: nightsDirectory).filter { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else {
                // Anything that is not a session UUID has no business here.
                return true
            }
            return !knownSessionIDs.contains(id)
        }
    }

    func incompleteSegmentFiles(for sessionID: UUID) -> [URL] {
        contents(of: segmentsDirectory(for: sessionID))
            .filter { $0.pathExtension == AudioConstants.inProgressExtension }
    }

    // MARK: - Helpers

    private func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += size(of: url)
        }
        return total
    }

    /// Raw audio is excluded from iCloud backup: a beta should not quietly fill
    /// someone's iCloud storage with hundreds of megabytes a night.
    private func excludeFromBackup(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try mutable.setResourceValues(values)
        } catch {
            // Non-fatal: worth knowing about, never worth refusing to record over.
            Log.storage.error("Could not exclude night directory from backup")
        }
    }
}
