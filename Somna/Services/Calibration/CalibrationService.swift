import AVFoundation
import Accelerate
import Foundation
import OSLog

/// Measures the room before the first night.
protocol CalibrationMeasuring: Sendable {
    /// Records for `duration` seconds and returns what it heard.
    ///
    /// - Throws: ``SomnaError/microphoneAccessDenied`` if permission is missing,
    ///   or ``AudioError`` if the input cannot be opened.
    func measure(duration: TimeInterval) async throws -> CalibrationAssessment
}

/// Real measurement, via `AVAudioEngine`.
///
/// This is the first audio code in the project and it deliberately exercises the
/// parts Phase 5 will depend on — session category, input tap, vDSP level
/// computation — on a fifteen-second task rather than on an eight-hour one.
/// A microphone that cannot be opened is much cheaper to discover here.
actor CalibrationService: CalibrationMeasuring {

    private let engine = AVAudioEngine()

    func measure(duration: TimeInterval) async throws -> CalibrationAssessment {
        try configureSession()

        let levels = try await captureLevels(for: duration)
        let assessment = PlacementQualityEvaluator.evaluate(levels: levels)

        Log.audio.info("Calibration finished: \(assessment.rating.rawValue, privacy: .public), \(assessment.issues.count, privacy: .public) issue(s)")
        return assessment
    }

    // MARK: - Session

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.measurement` mode matters here: it disables the input processing
            // chain — automatic gain, noise suppression — that iOS applies by
            // default. With AGC on, a silent room and a noisy one both measure
            // as "medium", which would make the noise floor meaningless and every
            // level derived from it a fiction.
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            Log.audio.error("Audio session could not be activated for calibration")
            throw AudioError.sessionUnavailable
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Capture

    private func captureLevels(for duration: TimeInterval) async throws -> [Double] {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            // Happens on a simulator with no host microphone, and on a device
            // where another app holds the input exclusively.
            Log.audio.error("Input node reported an unusable format")
            deactivateSession()
            throw AudioError.inputUnavailable
        }

        let collector = LevelCollector()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let level = Self.rootMeanSquare(of: buffer) else { return }
            Task { await collector.append(level) }
        }

        defer {
            input.removeTap(onBus: 0)
            engine.stop()
            deactivateSession()
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            Log.audio.error("Audio engine failed to start for calibration")
            throw AudioError.engineFailedToStart
        }

        try await Task.sleep(for: .seconds(duration))
        return await collector.levels
    }

    /// Normalised RMS of a buffer, 0–1.
    ///
    /// Uses vDSP rather than a Swift loop: this runs on the audio thread's tap
    /// callback, where allocation and slow arithmetic cause dropouts.
    private static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Double? {
        guard
            let channel = buffer.floatChannelData?[0],
            buffer.frameLength > 0
        else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))

        guard rms.isFinite else { return nil }
        return Double(min(max(rms, 0), 1))
    }
}

/// Collects levels from the audio tap.
///
/// An actor because the tap callback runs on a real-time audio thread that is
/// not part of the concurrency system: it must hand values off rather than
/// mutate shared state directly.
private actor LevelCollector {
    private(set) var levels: [Double] = []

    func append(_ level: Double) {
        levels.append(level)
    }
}

/// Calibration with a fixed answer, for previews and tests.
struct StubCalibrationService: CalibrationMeasuring {
    let assessment: CalibrationAssessment

    init(rating: CalibrationProfile.Rating = .excellent) {
        assessment = CalibrationAssessment(
            rating: rating,
            issues: [],
            noiseFloor: 0.04,
            variability: 0.01
        )
    }

    func measure(duration: TimeInterval) async throws -> CalibrationAssessment {
        // Kept short: a preview should not idle for fifteen seconds.
        try? await Task.sleep(for: .milliseconds(300))
        return assessment
    }
}
