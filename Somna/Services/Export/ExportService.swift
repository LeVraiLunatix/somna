import Foundation
import OSLog

/// Exports a night in a form the user owns.
///
/// Local files only, handed to the system share sheet. Somna never sends
/// anything anywhere itself — the user decides where an export goes, which is
/// the whole point of offering one in a local-first app.
///
/// **A whole night's audio can be exported, behind a confirmation.** This used
/// to be refused outright, on the grounds that sharing eight hours of a bedroom
/// is a privacy decision with consequences for anyone else who was in the room.
/// That reasoning was right about the risk and wrong about who decides: the
/// recording is the user's, and an app that keeps hours of their audio for a
/// week while offering no way to reach it has taken something without saying so.
///
/// So the refusal became a confirmation. The screen says plainly how long the
/// recording is and that anyone audible in the room is in it, and the export
/// happens only after that is acknowledged — deliberate rather than casual,
/// which was the defensible part of the original rule.
protocol NightExporting: Sendable {
    func exportJSON(session: NightSession, events: [NightEvent]) throws -> URL
    func exportCSV(session: NightSession, events: [NightEvent]) throws -> URL
    func summaryText(session: NightSession) -> String

    /// The night's raw audio, as a single archive of its segments.
    ///
    /// A night is stored as ten-minute segments — around 48 files for a full
    /// night — so handing over a folder as one archive is the only form that
    /// survives a share sheet intact.
    func exportAudio(session: NightSession) throws -> URL
}

struct ExportService: NightExporting {

    let files: any NightFileStoring

    /// Written to a temporary directory, not into the app's storage: an export
    /// is a copy for elsewhere, and keeping it would quietly double what a night
    /// costs on disk.
    private var exportDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SomnaExports", directoryHint: .isDirectory)
    }

    func exportJSON(session: NightSession, events: [NightEvent]) throws -> URL {
        let payload = NightExport(
            session: SessionExport(session),
            events: events.map(EventExport.init),
            exportedAt: Date(),
            appVersion: Bundle.main.displayVersion,
            analysisVersion: session.analysisVersion
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try write(
            try encoder.encode(payload),
            named: "somna-\(fileStamp(session.startDate)).json"
        )
    }

    func exportCSV(session: NightSession, events: [NightEvent]) throws -> URL {
        var rows = ["start,end,type,confidence,occurrences,peak,corrected"]

        let formatter = ISO8601DateFormatter()
        for event in events {
            rows.append([
                formatter.string(from: event.startDate),
                formatter.string(from: event.endDate),
                event.effectiveType.rawValue,
                event.effectiveConfidence.rawValue,
                "\(event.occurrenceCount)",
                String(format: "%.3f", event.peakLevel),
                event.userCorrectedType == nil ? "false" : "true",
            ].joined(separator: ","))
        }

        return try write(
            Data(rows.joined(separator: "\n").utf8),
            named: "somna-\(fileStamp(session.startDate)).csv"
        )
    }

    /// The summary as plain text, for pasting into a message or a note.
    func summaryText(session: NightSession) -> String {
        let date = session.startDate.formatted(date: .abbreviated, time: .omitted)
        let body = SummaryRenderer.paragraph(for: session.summaryStatements)

        // The disclaimer travels with the text. Once a summary leaves the app it
        // loses every piece of context the report gave it, and "snoring detected
        // for 40 minutes" read cold, out of a message, invites exactly the
        // medical reading Somna refuses to support.
        let disclaimer = String(
            localized: "export.disclaimer",
            defaultValue: "Recorded with Somna. Somna detects sounds; it is not a medical device and does not measure sleep."
        )

        return "\(date)\n\n\(body)\n\n\(disclaimer)"
    }

    func exportAudio(session: NightSession) throws -> URL {
        let segments = files.segmentsDirectory(for: session.id)

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: segments,
            includingPropertiesForKeys: nil
        )) ?? []
        let audio = contents.filter { $0.pathExtension == "m4a" }

        // An empty export is worse than a refused one: it looks like the night
        // was silent rather than like there is nothing to give.
        guard !audio.isEmpty else { throw SomnaError.exportEmpty }

        return try zip(segments, named: "somna-\(fileStamp(session.startDate))-audio.zip")
    }

    // MARK: - Helpers

    /// Zips a directory using the coordinator's `.forUploading` option.
    ///
    /// This is the system's own archiver — no dependency, and it produces the
    /// zip iOS itself would. The coordinator hands back a temporary URL that is
    /// deleted when the accessor returns, so the archive is copied out before
    /// then rather than shared from under itself.
    private func zip(_ directory: URL, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let destination = exportDirectory.appending(path: name)
        try? FileManager.default.removeItem(at: destination)

        var coordinationError: NSError?
        var copyError: (any Error)?

        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinationError
        ) { temporary in
            do {
                try FileManager.default.copyItem(at: temporary, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appending(path: name)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func fileStamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}

// MARK: - Wire format

/// The exported shape.
///
/// Deliberately separate from the domain models: an export is a contract with
/// whatever the user opens it in, and it must not change because an internal
/// type gained a field.
private struct NightExport: Encodable {
    let session: SessionExport
    let events: [EventExport]
    let exportedAt: Date
    let appVersion: String
    let analysisVersion: String
}

private struct SessionExport: Encodable {
    let id: UUID
    let start: Date
    let end: Date?
    let recordedSeconds: TimeInterval
    let calmnessScore: Int?
    let recordingQuality: String?
    let coverage: Double?
    let estimatedSleepStart: Date?
    let estimatedWakeTime: Date?

    init(_ session: NightSession) {
        id = session.id
        start = session.startDate
        end = session.endDate
        recordedSeconds = session.recordedDuration
        calmnessScore = session.calmnessScore
        recordingQuality = session.recordingQuality?.rating.rawValue
        coverage = session.captureCoverage
        estimatedSleepStart = session.estimatedSleepStart
        estimatedWakeTime = session.estimatedWakeTime
    }
}

private struct EventExport: Encodable {
    let start: Date
    let end: Date
    let type: String
    let modelType: String
    let confidence: String
    let occurrences: Int
    let peakLevel: Double
    let correctedByUser: Bool

    init(_ event: NightEvent) {
        start = event.startDate
        end = event.endDate
        type = event.effectiveType.rawValue
        // The model's own guess ships alongside the corrected value: anyone
        // analysing an export deserves to see where the app was wrong.
        modelType = event.type.rawValue
        confidence = event.effectiveConfidence.rawValue
        occurrences = event.occurrenceCount
        peakLevel = event.peakLevel
        correctedByUser = event.userCorrectedType != nil
    }
}
