import Foundation
import OSLog

/// Exports a night in a form the user owns.
///
/// Local files only, handed to the system share sheet. Somna never sends
/// anything anywhere itself — the user decides where an export goes, which is
/// the whole point of offering one in a local-first app.
///
/// **Whole recordings are never exported.** Sharing eight hours of a bedroom is
/// a privacy decision with consequences for anyone else who was in the room, and
/// it is not one to make casually from a share sheet. Reports, event data and
/// individually chosen clips are.
protocol NightExporting: Sendable {
    func exportJSON(session: NightSession, events: [NightEvent]) throws -> URL
    func exportCSV(session: NightSession, events: [NightEvent]) throws -> URL
    func summaryText(session: NightSession) -> String
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

    // MARK: - Helpers

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
