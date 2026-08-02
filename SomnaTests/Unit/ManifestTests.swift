import Foundation
import Testing

@testable import Somna

/// The manifest is the answer to "what if SwiftData loses a night".
///
/// These tests treat it as the recovery path it is, not as a serialisation
/// detail: they check that a night interrupted mid-write is still
/// reconstructible, and that a manifest Somna does not understand is refused
/// rather than half-read.
struct ManifestTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> (NightFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SomnaManifest-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (NightFileStore(root: root), root)
    }

    private func segment(_ index: Int, sessionID: UUID) -> AudioSegment {
        AudioSegment(
            sessionID: sessionID,
            fileName: String(format: "seg-%03d.m4a", index),
            startDate: start.addingTimeInterval(Double(index) * 600),
            endDate: start.addingTimeInterval(Double(index + 1) * 600),
            fileSize: 2_400_000,
            processingState: .ready
        )
    }

    @Test("A finished night round-trips through disk")
    func roundTrip() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        let manifest = NightManifest(
            sessionID: id,
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            recordedDuration: 7.5 * 3600,
            segments: [segment(0, sessionID: id), segment(1, sessionID: id)],
            gaps: [RecordingGap(start: start.addingTimeInterval(3600),
                                end: start.addingTimeInterval(3900))],
            stopReason: .userRequested
        )
        try manifest.write(using: store)

        let loaded = try #require(NightManifest.read(sessionID: id, using: store))
        #expect(loaded == manifest)
        #expect(loaded.segments.count == 2)
        #expect(loaded.gaps.first?.duration == 300)
    }

    /// The scenario the manifest exists for: the app died before it could write
    /// an end date. The night must still come back, with its audio, marked as
    /// interrupted rather than as a failure.
    @Test("A night that never ended is reconstructible and marked interrupted")
    func unfinishedNightIsRecoverable() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        try NightManifest(
            sessionID: id,
            startDate: start,
            endDate: nil,
            recordedDuration: 2 * 3600,
            segments: [segment(0, sessionID: id), segment(1, sessionID: id)],
            gaps: [],
            stopReason: nil
        ).write(using: store)

        let loaded = try #require(NightManifest.read(sessionID: id, using: store))
        let session = loaded.reconstructedSession(now: start.addingTimeInterval(9 * 3600))

        #expect(session.id == id)
        #expect(session.status == .interrupted)
        #expect(session.recordedDuration == 2 * 3600)
        // The end is inferred from the last segment, so the night has a real
        // span rather than appearing to still be running.
        #expect(session.endDate == segment(1, sessionID: id).endDate)
        #expect(loaded.reconstructedSegments().count == 2)
    }

    @Test("Segments come back with the file names they were written under")
    func segmentsSurvive() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        try NightManifest(
            sessionID: id,
            startDate: start,
            endDate: start.addingTimeInterval(600),
            recordedDuration: 600,
            segments: [segment(0, sessionID: id)],
            gaps: [],
            stopReason: .userRequested
        ).write(using: store)

        let rebuilt = try #require(NightManifest.read(sessionID: id, using: store)).reconstructedSegments()
        #expect(rebuilt.first?.fileName == "seg-000.m4a")
        #expect(rebuilt.first?.sessionID == id)
        #expect(rebuilt.first?.isUsable == true)
    }

    /// Rewritten after every segment, so each write must replace the previous
    /// one cleanly rather than appending or corrupting it.
    @Test("Rewriting the manifest replaces it")
    func rewritingReplaces() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        for count in 1...3 {
            try NightManifest(
                sessionID: id,
                startDate: start,
                endDate: nil,
                recordedDuration: Double(count) * 600,
                segments: (0..<count).map { segment($0, sessionID: id) },
                gaps: [],
                stopReason: nil
            ).write(using: store)
        }

        let loaded = try #require(NightManifest.read(sessionID: id, using: store))
        #expect(loaded.segments.count == 3)
        #expect(loaded.recordedDuration == 1800)
    }

    @Test("A missing manifest is absence, not an error")
    func missingManifest() {
        let (store, _) = makeStore()
        #expect(NightManifest.read(sessionID: UUID(), using: store) == nil)
    }

    @Test("A corrupt manifest is refused rather than half-read")
    func corruptManifest() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)
        try store.writeAtomically(
            Data("{ not json".utf8),
            to: store.sessionDirectory(for: id).appending(path: NightManifest.fileName)
        )

        #expect(NightManifest.read(sessionID: id, using: store) == nil)
    }

    /// Refusing beats guessing: a half-understood manifest could produce a night
    /// with the wrong duration or with segments silently missing.
    @Test("A manifest from a newer build is refused")
    func futureVersionIsRefused() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try store.prepareDirectories(for: id)

        var manifest = NightManifest(
            sessionID: id,
            startDate: start,
            endDate: nil,
            recordedDuration: 600,
            segments: [],
            gaps: [],
            stopReason: nil
        )
        manifest.version = NightManifest.currentVersion + 1
        try manifest.write(using: store)

        #expect(NightManifest.read(sessionID: id, using: store) == nil)
    }
}

struct MetricsTests {

    @Test("Metrics round-trip through JSON Lines")
    func metricsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SomnaMetrics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "seg-000.features.jsonl")
        let writer = MetricsWriter(url: url)

        let batch = (0..<50).map {
            AudioMetrics(offset: Double($0) * 0.1, rms: 0.05, peak: 0.2, zeroCrossingRate: 0.3)
        }
        try writer.append(batch)
        try writer.append(batch)

        let read = try MetricsWriter.read(from: url)
        #expect(read.count == 100)
        #expect(read.first?.offset == 0)
    }

    /// A crash mid-write leaves a truncated final line. It must cost that line
    /// and nothing else — the eight hours before it are still valid.
    @Test("A truncated final line is discarded, not fatal")
    func truncatedLineIsSurvivable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SomnaMetrics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "seg-000.features.jsonl")
        try MetricsWriter(url: url).append([
            AudioMetrics(offset: 0, rms: 0.1, peak: 0.2, zeroCrossingRate: 0.3),
            AudioMetrics(offset: 0.1, rms: 0.1, peak: 0.2, zeroCrossingRate: 0.3),
        ])

        var data = try Data(contentsOf: url)
        data.append(contentsOf: Data(#"{"offset":0.2,"rms":0.1,"pe"#.utf8))
        try data.write(to: url)

        let read = try MetricsWriter.read(from: url)
        #expect(read.count == 2)
    }

    @Test("An empty batch writes nothing")
    func emptyBatch() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SomnaMetrics-\(UUID().uuidString).jsonl")
        try MetricsWriter(url: url).append([])
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
