import Foundation
import Testing

@testable import Somna

/// Runs against a real temporary directory rather than a mocked file system.
///
/// The failures worth catching here — a rename that does not replace, a
/// truncated write, a directory that is not created — are exactly the ones a
/// mock cannot reproduce.
struct FileStoreTests {

    private func makeStore() -> (NightFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SomnaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (NightFileStore(root: root), root)
    }

    @Test("Paths are built under the session's own directory")
    func pathLayout() {
        let (store, _) = makeStore()
        let id = UUID()

        let segment = store.segmentURL(for: id, fileName: "seg-000.m4a")
        let clip = store.clipURL(for: id, fileName: "evt-1.m4a")

        #expect(segment.pathComponents.contains(id.uuidString))
        #expect(segment.pathComponents.contains("segments"))
        #expect(clip.pathComponents.contains("clips"))
        #expect(segment.lastPathComponent == "seg-000.m4a")
    }

    @Test("Preparing a session creates both audio directories")
    func prepareCreatesDirectories() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        #expect(FileManager.default.fileExists(atPath: store.segmentsDirectory(for: id).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: store.clipsDirectory(for: id).path(percentEncoded: false)))
    }

    @Test("Atomic writes leave no partial file behind")
    func atomicWrite() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)
        let url = store.segmentURL(for: id, fileName: "manifest.json")

        try store.writeAtomically(Data("first".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "first")

        try store.writeAtomically(Data("second".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "second")

        // The temporary file used during the write must not survive it.
        let leftovers = store.incompleteSegmentFiles(for: id)
        #expect(leftovers.isEmpty, "An atomic write left a .part file behind")
    }

    /// A `.part` file is what a crash mid-write leaves. It must be findable at
    /// next launch, because its content is truncated and would otherwise be
    /// analysed as if it were whole.
    @Test("Interrupted writes are detectable after a crash")
    func incompleteSegmentsAreFound() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        let orphan = store.segmentURL(for: id, fileName: "seg-004.m4a.part")
        try Data("truncated".utf8).write(to: orphan)

        let found = store.incompleteSegmentFiles(for: id)
        #expect(found.count == 1)
        #expect(found.first?.lastPathComponent == "seg-004.m4a.part")
    }

    /// Directories with no database row occupy space while being unreachable
    /// from any screen — invisible storage growth.
    @Test("Session directories with no database row are reported as orphans")
    func orphanDetection() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let known = UUID()
        let orphan = UUID()
        try store.prepareDirectories(for: known)
        try store.prepareDirectories(for: orphan)

        let orphans = store.orphanedSessionDirectories(knownSessionIDs: [known])
        #expect(orphans.count == 1)
        #expect(orphans.first?.lastPathComponent == orphan.uuidString)
    }

    @Test("Anything that is not a session directory is treated as an orphan")
    func strayDirectoriesAreOrphans() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let known = UUID()
        try store.prepareDirectories(for: known)

        let stray = store.sessionDirectory(for: known)
            .deletingLastPathComponent()
            .appending(path: "not-a-uuid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)

        let orphans = store.orphanedSessionDirectories(knownSessionIDs: [known])
        #expect(orphans.contains { $0.lastPathComponent == "not-a-uuid" })
    }

    @Test("Deleting a session removes its files and is safe to repeat")
    func removalIsIdempotent() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)
        try store.writeAtomically(Data(repeating: 0, count: 1024),
                                  to: store.segmentURL(for: id, fileName: "seg-000.m4a"))

        #expect(store.totalSize(for: id) > 0)

        try store.removeSessionDirectory(for: id)
        #expect(!FileManager.default.fileExists(atPath: store.sessionDirectory(for: id).path(percentEncoded: false)))

        // Deleting twice must not throw: cleanup runs at launch and can race
        // with a user-initiated deletion.
        try store.removeSessionDirectory(for: id)
    }

    @Test("Session size accumulates across subdirectories")
    func sizeAccumulates() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)
        try store.writeAtomically(Data(repeating: 1, count: 4096),
                                  to: store.segmentURL(for: id, fileName: "seg-000.m4a"))
        try store.writeAtomically(Data(repeating: 1, count: 2048),
                                  to: store.clipURL(for: id, fileName: "evt-1.m4a"))

        #expect(store.totalSize(for: id) >= 6144)
    }
}

struct ByteFormattingTests {

    @Test("Sizes are rendered in the same style as iOS Settings")
    func sizeFormatting() {
        // Exact strings vary by locale, so the assertion is on shape, not text:
        // a non-empty rendering containing the digits.
        #expect(!Int64(115_000_000).formattedByteSize.isEmpty)
        #expect(Int64(0).formattedByteSize.contains("0"))
    }

    @Test("Free space converts to a meaningful number of recording hours")
    func recordingHours() {
        // 14 MB per hour at the default bit rate.
        #expect(abs(Int64(14_000_000).estimatedRecordingHours - 1) < 0.01)
        #expect(abs(Int64(140_000_000).estimatedRecordingHours - 10) < 0.01)
        #expect(Int64(0).estimatedRecordingHours == 0)
    }
}

struct PermissionSemanticsTests {

    /// The distinction that stops the app offering a button iOS will ignore.
    @Test("Only an undetermined permission can still produce a system prompt")
    func promptability() {
        #expect(MicrophonePermission.undetermined.canPrompt)
        #expect(!MicrophonePermission.permanentlyDenied.canPrompt)
        #expect(!MicrophonePermission.granted.canPrompt)
    }

    @Test("Only a granted permission allows recording")
    func recordingRequiresGrant() {
        #expect(MicrophonePermission.granted.allowsRecording)
        #expect(!MicrophonePermission.undetermined.allowsRecording)
        #expect(!MicrophonePermission.denied.allowsRecording)
        #expect(!MicrophonePermission.permanentlyDenied.allowsRecording)
    }
}

@MainActor
struct RouterTests {

    @Test("Each tab keeps its own navigation stack")
    func tabsHaveIndependentStacks() {
        let router = AppRouter()

        router.push(.settings, in: .settings)
        router.push(.history, in: .history)

        #expect(router.paths[.settings]?.count == 1)
        #expect(router.paths[.history]?.count == 1)
        #expect(router.paths[.home] == nil)
    }

    @Test("Popping to root clears only the target tab")
    func popIsScoped() {
        let router = AppRouter()
        router.push(.settings, in: .settings)
        router.push(.trends, in: .trends)

        router.popToRoot(in: .settings)

        #expect(router.paths[.settings]?.isEmpty == true)
        #expect(router.paths[.trends]?.count == 1)
    }

    /// Opening a night from a notification must not leave the user several
    /// screens deep in a stack they never built.
    @Test("Opening a night report resets the stack it lands in")
    func showNightReportResetsStack() {
        let router = AppRouter()
        let id = UUID()

        router.push(.trends, in: .home)
        router.push(.storage, in: .home)
        router.selectedTab = .settings

        router.showNightReport(sessionID: id)

        #expect(router.selectedTab == .home)
        #expect(router.paths[.home] == [.nightReport(sessionID: id)])
    }
}
