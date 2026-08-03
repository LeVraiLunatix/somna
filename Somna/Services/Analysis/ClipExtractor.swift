import AVFoundation
import Foundation
import OSLog

/// Cuts the short excerpt that sits behind every event.
///
/// This is what makes Somna checkable rather than merely assertive: a timeline
/// row saying "likely cough" is a claim, and the clip is the evidence. An event
/// whose clip could not be extracted is still shown — the detection happened —
/// but the report is then relying on trust it has not earned, so extraction
/// failures are logged rather than silently accepted.
struct ClipExtractor: Sendable {

    /// How many envelope samples a mini-waveform carries.
    ///
    /// Sized for the width of a timeline row: more would be invisible detail
    /// stored forever, fewer would render as blocks.
    static let waveformResolution = 60

    struct Clip: Sendable {
        let fileName: String
        let waveform: [Float]
        let peak: Float
    }

    let bitRate: Int

    init(bitRate: Int = AudioConstants.defaultBitRate) {
        self.bitRate = bitRate
    }

    /// Extracts `range` from `sourceURL` into the session's clip folder.
    ///
    /// - Parameter range: offsets in seconds, relative to the start of the
    ///   source file.
    func extract(
        from sourceURL: URL,
        range: ClosedRange<TimeInterval>,
        eventID: UUID,
        destinationDirectory: URL
    ) -> Clip? {
        do {
            let input = try AVAudioFile(forReading: sourceURL)
            let format = input.processingFormat
            let sampleRate = format.sampleRate
            guard sampleRate > 0 else { return nil }

            // Padding is applied here rather than by the caller so a clip near
            // the start or end of a segment is clamped rather than failing.
            let padded = max(0, range.lowerBound - AnalysisConstants.clipPadding)
                ... (range.upperBound + AnalysisConstants.clipPadding)

            let startFrame = AVAudioFramePosition(padded.lowerBound * sampleRate)
            let frameCount = AVAudioFrameCount(
                min(
                    (padded.upperBound - padded.lowerBound) * sampleRate,
                    Double(input.length) - Double(startFrame)
                )
            )
            guard startFrame < input.length, frameCount > 0 else { return nil }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }

            input.framePosition = startFrame
            try input.read(into: buffer, frameCount: frameCount)

            let fileName = "evt-\(eventID.uuidString).\(AudioConstants.segmentExtension)"
            let destination = destinationDirectory.appending(path: fileName)

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: bitRate,
            ]

            let output = try AVAudioFile(forWriting: destination, settings: settings)
            try output.write(from: buffer)

            let (waveform, peak) = envelope(of: buffer)
            return Clip(fileName: fileName, waveform: waveform, peak: peak)

        } catch {
            // Never fatal. A missing clip weakens one row; failing the analysis
            // would cost the whole night.
            Log.analysis.error("Clip extraction failed for one event")
            return nil
        }
    }

    /// Downsamples a buffer to a fixed-size envelope.
    ///
    /// Peak per bucket rather than mean: a mean envelope of a cough is a flat
    /// line, which tells the eye nothing about what it is looking at.
    private func envelope(of buffer: AVAudioPCMBuffer) -> ([Float], Float) {
        guard
            let channel = buffer.floatChannelData?[0],
            buffer.frameLength > 0
        else { return ([], 0) }

        let frames = Int(buffer.frameLength)
        let bucketSize = max(1, frames / Self.waveformResolution)

        var envelope: [Float] = []
        envelope.reserveCapacity(Self.waveformResolution)
        var overallPeak: Float = 0

        var index = 0
        while index < frames {
            let end = min(index + bucketSize, frames)
            var peak: Float = 0
            for position in index..<end {
                peak = max(peak, abs(channel[position]))
            }
            envelope.append(min(1, peak))
            overallPeak = max(overallPeak, peak)
            index = end
        }

        return (envelope, min(1, overallPeak))
    }
}
