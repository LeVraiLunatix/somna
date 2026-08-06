import Foundation

/// Recording parameters, fixed in Phase 1 and justified there.
///
/// Changing any of these invalidates comparisons with previously recorded
/// nights, so they are constants rather than settings, and any change must bump
/// ``AnalysisConstants/currentVersion``.
enum AudioConstants {

    /// 16 kHz. Snoring, coughing and speech carry their useful energy below
    /// 8 kHz, which this satisfies under Nyquist. 44.1 kHz would triple storage
    /// and energy cost for no classification benefit.
    static let sampleRate: Double = 16_000

    /// Mono. Only one microphone is used; a second channel would double the file
    /// size while carrying no additional information.
    static let channelCount: Int = 1

    /// AAC-LC at 32 kbps ≈ 14 MB per hour, ≈ 115 MB for a full night.
    /// Uncompressed PCM at the same sample rate would be ≈ 920 MB.
    static let defaultBitRate: Int = 32_000

    /// How often the running session screen is refreshed, in seconds of
    /// captured audio.
    ///
    /// One second, because that is the granularity the screen shows: the clock
    /// reads `m:ss`, so publishing faster would wake the main actor to redraw
    /// pixels that cannot have changed. Buffers arrive several times a second
    /// and this runs for eight hours on a phone that has to survive the night —
    /// the difference between 1 Hz and 10 Hz is nearly 300 000 needless hops.
    static let statusPublishInterval: TimeInterval = 1

    /// Offered in Settings for users who would rather spend the disk space.
    static let highQualityBitRate: Int = 64_000

    /// How much captured audio passes between manifest rewrites.
    ///
    /// The manifest used to be written only when a segment closed — every ten
    /// minutes — so a night that ended without a clean stop recovered with
    /// whatever duration the last rotation had recorded. A night shorter than a
    /// single segment recovered as **zero**, which the report showed as `0:00`
    /// beside audio that was plainly on disk.
    ///
    /// Fifteen seconds costs a few kilobytes written atomically, against
    /// knowing within fifteen seconds how much of a night survived a crash.
    static let manifestInterval: TimeInterval = 15

    /// Ten minutes. A crash costs at most one segment, never the night.
    static let segmentDuration: TimeInterval = 10 * 60

    /// Written to a `.part` file and renamed on close, so an interrupted write
    /// is detectable at next launch rather than silently truncated.
    static let inProgressExtension = "part"
    static let segmentExtension = "m4a"

    /// Refuse to start a session below this much free space. A night that runs
    /// out of disk at 03:00 is worse than a night that never started.
    static let minimumFreeSpaceToRecord: Int64 = 1_500_000_000

    /// Rough disk cost per hour at the default bit rate, used for the estimate
    /// shown on the preparation screen.
    static let estimatedBytesPerHour: Int64 = 14_000_000
}
