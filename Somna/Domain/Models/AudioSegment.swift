import Foundation

/// A ten-minute slice of a night's audio.
///
/// Nights are stored as many small files rather than one large one so a crash
/// costs at most one segment, and so retention can delete raw audio while
/// keeping extracted clips.
struct AudioSegment: Identifiable, Equatable, Sendable {

    /// Where a segment is in the analysis pipeline.
    enum ProcessingState: String, Codable, Sendable {
        /// Being written to right now.
        case recording
        /// Closed and verified, waiting for analysis.
        case ready
        case analyzing
        case analyzed
        /// Unreadable or truncated; skipped without failing the whole night.
        case corrupted
    }

    /// Whether the underlying audio still exists on disk.
    enum RetentionState: String, Codable, Sendable {
        case present
        /// Raw audio deleted by the retention policy; extracted clips survive.
        case purged
    }

    let id: UUID
    let sessionID: UUID

    /// File name relative to the session's segment folder — never an absolute
    /// path, which iOS invalidates when it relocates the app container.
    var fileName: String

    var startDate: Date
    var endDate: Date
    var sampleRate: Double
    var channelCount: Int
    var fileSize: Int64
    var processingState: ProcessingState
    var retentionState: RetentionState

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        fileName: String,
        startDate: Date,
        endDate: Date,
        sampleRate: Double = AudioConstants.sampleRate,
        channelCount: Int = AudioConstants.channelCount,
        fileSize: Int64 = 0,
        processingState: ProcessingState = .recording,
        retentionState: RetentionState = .present
    ) {
        self.id = id
        self.sessionID = sessionID
        self.fileName = fileName
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fileSize = fileSize
        self.processingState = processingState
        self.retentionState = retentionState
    }
}

extension AudioSegment {
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Whether this segment can still be analysed or played back.
    var isUsable: Bool {
        retentionState == .present && processingState != .corrupted
    }
}
