import AVFoundation
import Foundation
import OSLog

/// Writes one ten-minute segment, and hands over cleanly.
///
/// Every segment is written to `<name>.part` and renamed on close. A file that
/// still carries `.part` at the next launch is, by construction, one that was
/// being written when the app died — detectable rather than silently truncated
/// and analysed as if it were whole.
///
/// Not an actor: it is only ever touched from `AudioRecordingEngine`'s isolation
/// domain, and adding a second hop between the audio tap and the disk would buy
/// nothing.
final class SegmentWriter {

    let index: Int
    let startDate: Date
    let finalURL: URL

    /// PCM format the file expects. Buffers must be converted to this before
    /// being written; `AVAudioFile` encodes to AAC on the way out.
    let processingFormat: AVAudioFormat

    private let partURL: URL
    private var file: AVAudioFile?
    private(set) var framesWritten: AVAudioFramePosition = 0

    init(index: Int, startDate: Date, directory: URL, bitRate: Int) throws {
        self.index = index
        self.startDate = startDate

        let name = String(format: "seg-%03d.%@", index, AudioConstants.segmentExtension)
        finalURL = directory.appending(path: name)
        partURL = directory.appending(path: name + "." + AudioConstants.inProgressExtension)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioConstants.sampleRate,
            AVNumberOfChannelsKey: AudioConstants.channelCount,
            AVEncoderBitRateKey: bitRate,
        ]

        do {
            let file = try AVAudioFile(forWriting: partURL, settings: settings)
            self.file = file
            processingFormat = file.processingFormat
        } catch {
            Log.audio.error("Segment \(index, privacy: .public) could not be opened for writing")
            throw AudioError.engineFailedToStart
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let file else { return }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            Log.audio.error("Segment \(self.index, privacy: .public) write failed")
            throw AudioError.engineFailedToStart
        }
    }

    var duration: TimeInterval {
        Double(framesWritten) / AudioConstants.sampleRate
    }

    /// Closes the file and publishes it under its final name.
    ///
    /// - Returns: the finished segment, or `nil` if nothing was ever written —
    ///   an empty segment is deleted rather than published, so the database never
    ///   references a file with no audio in it.
    @discardableResult
    func finish(sessionID: UUID, endDate: Date) -> AudioSegment? {
        // Releasing the file is what flushes the encoder and writes the atom
        // table. Renaming before this would publish an unplayable file.
        file = nil

        guard framesWritten > 0 else {
            try? FileManager.default.removeItem(at: partURL)
            return nil
        }

        do {
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: partURL)
        } catch {
            Log.audio.error("Segment \(self.index, privacy: .public) could not be published")
            return nil
        }

        let size = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return AudioSegment(
            sessionID: sessionID,
            fileName: finalURL.lastPathComponent,
            startDate: startDate,
            endDate: endDate,
            fileSize: Int64(size),
            processingState: .ready
        )
    }
}

/// Converts tap buffers into the format the segment file expects.
///
/// The microphone delivers whatever the hardware uses — typically 48 kHz, often
/// more than one channel. Somna stores 16 kHz mono. Without this conversion
/// `AVAudioFile.write(from:)` rejects the buffer, and the night records nothing.
final class AudioFormatConverter {

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard
            inputFormat.sampleRate > 0,
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }

        self.converter = converter
        self.outputFormat = outputFormat
        ratio = outputFormat.sampleRate / inputFormat.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1

        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?

        converter.convert(to: output, error: &error) { _, status in
            // The converter asks repeatedly; a second yield of the same buffer
            // would duplicate audio, so the input is offered exactly once.
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        if let error {
            Log.audio.error("Format conversion failed: \(error.code, privacy: .public)")
            return nil
        }

        return output.frameLength > 0 ? output : nil
    }
}
