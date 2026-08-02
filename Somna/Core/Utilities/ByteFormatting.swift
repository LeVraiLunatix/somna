import Foundation

extension Int64 {

    /// Human-readable file size, e.g. `115 MB`.
    ///
    /// Uses `.file` count style so the figure matches what iOS Settings shows
    /// for the app. A storage screen that disagrees with Settings makes people
    /// distrust both.
    var formattedByteSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }

    /// Rough hours of recording this many bytes represents, at the default
    /// bit rate. Used for the estimate on the preparation screen.
    var estimatedRecordingHours: Double {
        guard AudioConstants.estimatedBytesPerHour > 0 else { return 0 }
        return Double(self) / Double(AudioConstants.estimatedBytesPerHour)
    }
}
