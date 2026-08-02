import Accelerate
import AVFoundation
import Foundation

/// One measurement window during the night.
///
/// Written as JSON Lines beside each segment so the morning pass can pick
/// candidate zones without decoding eight hours of audio first.
struct AudioMetrics: Codable, Equatable, Sendable {
    /// Seconds since the session started.
    let offset: TimeInterval
    /// Root mean square level, 0–1.
    let rms: Float
    /// Highest sample magnitude in the window, 0–1.
    let peak: Float
    /// Zero crossings per sample, 0–1. High for fricatives and rustling, low
    /// for snoring and hum — cheap and surprisingly discriminating.
    let zeroCrossingRate: Float
}

/// Computes per-buffer metrics.
///
/// **Deliberately no FFT.** Phase 1 planned a spectral centroid here, and it has
/// been moved to the morning pass. The reason is battery: an FFT on every buffer
/// for eight hours is the single most expensive thing this app could do at
/// night, and the morning pass has the full audio anyway — computing spectra
/// there costs nothing extra while the phone is awake and charging. What remains
/// is enough to find candidate zones, which is all the night pass has to do.
///
/// All arithmetic goes through vDSP: this runs inside the audio tap callback,
/// where allocation and slow loops cause dropouts that would appear as gaps in
/// someone's night.
enum RealtimeMetricsExtractor {

    static func metrics(from buffer: AVAudioPCMBuffer, offset: TimeInterval) -> AudioMetrics? {
        guard
            let channel = buffer.floatChannelData?[0],
            buffer.frameLength > 0
        else { return nil }

        let count = vDSP_Length(buffer.frameLength)

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, count)

        var peak: Float = 0
        vDSP_maxmgv(channel, 1, &peak, count)

        let zcr = zeroCrossingRate(channel, frameCount: Int(buffer.frameLength))

        guard rms.isFinite, peak.isFinite else { return nil }

        return AudioMetrics(
            offset: offset,
            rms: min(max(rms, 0), 1),
            peak: min(max(peak, 0), 1),
            zeroCrossingRate: zcr
        )
    }

    /// Fraction of adjacent sample pairs that change sign.
    private static func zeroCrossingRate(_ samples: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 1 else { return 0 }

        var lastCrossing: vDSP_Length = 0
        var crossingCount: vDSP_Length = 0

        // Asking for `frameCount` crossings means "find them all"; the routine
        // stops early if there are fewer.
        vDSP_nzcros(
            samples,
            1,
            vDSP_Length(frameCount),
            &lastCrossing,
            &crossingCount,
            vDSP_Length(frameCount)
        )

        return min(1, Float(crossingCount) / Float(frameCount - 1))
    }
}

/// Writes metrics as JSON Lines.
///
/// One line per window, appended. The format is chosen so a crash mid-write
/// costs one line rather than the whole file: a truncated final line is
/// discarded on read, and everything before it is still valid.
struct MetricsWriter {

    private let url: URL
    private let encoder = JSONEncoder()

    init(url: URL) {
        self.url = url
    }

    /// Appends a batch. Batched rather than per-buffer because opening a file
    /// handle ten times a second for eight hours is a needless amount of I/O.
    func append(_ batch: [AudioMetrics]) throws {
        guard !batch.isEmpty else { return }

        var payload = Data()
        for metrics in batch {
            payload.append(try encoder.encode(metrics))
            payload.append(0x0A)
        }

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: [.atomic])
        }
    }

    /// Reads back a metrics file, discarding a truncated final line.
    static func read(from url: URL) throws -> [AudioMetrics] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        return data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(AudioMetrics.self, from: Data($0)) }
    }
}
