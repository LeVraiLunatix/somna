import AVFoundation
import Foundation
import OSLog

/// Records a night.
///
/// An `actor` so the tap callback, the notification stream and the session
/// screen never touch the same state concurrently. Audio buffers arrive on a
/// real-time thread that is outside the concurrency system entirely, so they are
/// handed across rather than acted on in place.
///
/// The design commitment worth stating: **a crash costs at most one segment.**
/// Segments close every ten minutes, publish atomically, and are appended to a
/// manifest on disk as they land. Nothing about recovering a night depends on
/// the app shutting down cleanly, because the cases worth recovering from are
/// exactly the ones where it did not.
actor AudioRecordingEngine: AudioRecording {

    private let files: any NightFileStoring
    private let clock: any Clocking
    private let session = AudioSessionController()

    private var engine = AVAudioEngine()
    private var state: RecordingState = .idle

    private var sessionID: UUID?
    private var startDate: Date?
    private var bitRate = AudioConstants.defaultBitRate

    private var writer: SegmentWriter?
    private var converter: AudioFormatConverter?
    private var segmentIndex = 0
    private var completedSegments: [AudioSegment] = []
    private var gaps: [RecordingGap] = []

    private var recordedDuration: TimeInterval = 0
    private var currentLevel: Float = 0
    private var bytesWritten: Int64 = 0

    private var pendingMetrics: [AudioMetrics] = []
    private var metricsWriter: MetricsWriter?

    private var eventTask: Task<Void, Never>?
    private var statusContinuation: AsyncStream<RecordingStatus>.Continuation?

    init(files: any NightFileStoring, clock: any Clocking) {
        self.files = files
        self.clock = clock
    }

    // MARK: - Public surface

    func currentStatus() -> RecordingStatus {
        RecordingStatus(
            state: state,
            recordedDuration: recordedDuration,
            level: currentLevel,
            segmentCount: completedSegments.count,
            bytesWritten: bytesWritten
        )
    }

    func statusStream() -> AsyncStream<RecordingStatus> {
        AsyncStream { continuation in
            statusContinuation = continuation
            continuation.yield(currentStatus())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearStatusContinuation() }
            }
        }
    }

    private func clearStatusContinuation() {
        statusContinuation = nil
    }

    func start(sessionID: UUID, bitRate: Int) async throws {
        guard state == .idle else { return }

        self.sessionID = sessionID
        self.bitRate = bitRate
        startDate = clock.now
        segmentIndex = 0
        completedSegments = []
        gaps = []
        recordedDuration = 0
        bytesWritten = 0

        apply(.start)

        try files.prepareDirectories(for: sessionID)
        observeSessionEvents()

        do {
            try session.activateForRecording()
            try openSegment()
            try startEngine()
            apply(.engineStarted)
            Log.audio.info("Recording started for \(Log.short(sessionID), privacy: .public)")
        } catch let error as AudioError {
            apply(.failure(error))
            await teardown()
            throw error
        }
    }

    func stop(reason: StopReason) async throws -> RecordingOutcome {
        guard let sessionID, let startDate else { throw AudioError.engineFailedToStart }

        apply(.stopRequested(reason: reason))
        closeCurrentSegment()
        await teardown()
        apply(.engineStopped)

        let outcome = RecordingOutcome(
            sessionID: sessionID,
            startDate: startDate,
            endDate: clock.now,
            recordedDuration: recordedDuration,
            segments: completedSegments,
            gaps: gaps,
            stopReason: reason
        )

        do {
            try writeManifest(outcome)
        } catch {
            // Not fatal — the segments are on disk and the database row is
            // written — but the manifest is the recovery path, so losing it
            // silently would defeat the one thing it exists for.
            Log.storage.error("Final manifest could not be written; recovery would fall back to the database alone")
        }
        Log.audio.info("Recording stopped: \(reason.rawValue, privacy: .public), \(self.completedSegments.count, privacy: .public) segment(s)")

        self.sessionID = nil
        self.startDate = nil
        state = .idle
        publishStatus()

        return outcome
    }

    // MARK: - State

    private func apply(_ event: RecordingEvent) {
        guard let next = RecordingStateMachine.next(from: state, on: event) else { return }

        // A gap closes the moment capture resumes, and its real span is recorded
        // — a twenty-minute phone call must not appear on the timeline as an
        // instant, because that would make a broken night look intact.
        if let since = state.interruptedSince, next.isCapturing {
            gaps.append(RecordingGap(start: since, end: clock.now))
        }

        state = next
        publishStatus()
    }

    private func publishStatus() {
        statusContinuation?.yield(currentStatus())
    }

    // MARK: - Session events

    private func observeSessionEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in AudioSessionEvents.stream(clock: await self.clock) {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: RecordingEvent) async {
        switch event {
        case .interruptionBegan:
            // The engine is already stopped by iOS at this point. Closing the
            // segment publishes what was captured, so an interruption that never
            // ends still leaves a playable file rather than a `.part`.
            apply(event)
            closeCurrentSegment()
            engine.stop()

        case .interruptionEnded:
            apply(event)
            await attemptResume()

        case .mediaServicesReset:
            apply(event)
            closeCurrentSegment()
            // Every audio object is invalid, so the engine is replaced rather
            // than restarted.
            engine = AVAudioEngine()
            await attemptResume()

        default:
            apply(event)
        }
    }

    private func attemptResume() async {
        guard case .resuming = state else { return }

        do {
            try session.activateForRecording()
            try openSegment()
            try startEngine()
            apply(.engineResumed)
            Log.audio.info("Recording resumed after interruption")
        } catch let error as AudioError {
            // Back to interrupted, not failed: another interruption-ended
            // notification may still arrive, and everything already written stays.
            apply(.failure(error))
            Log.audio.error("Resume attempt failed; staying interrupted")
        } catch {
            apply(.failure(.engineFailedToStart))
        }
    }

    // MARK: - Engine

    private func startEngine() throws {
        guard let writer else { throw AudioError.engineFailedToStart }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.inputUnavailable
        }

        guard let converter = AudioFormatConverter(
            from: inputFormat,
            to: writer.processingFormat
        ) else {
            throw AudioError.inputUnavailable
        }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // Copy out of the real-time thread immediately: the audio unit reuses
            // its buffer as soon as this callback returns, so holding the original
            // across an await would read memory that is being overwritten.
            guard let copy = buffer.deepCopy() else { return }
            let transfer = AudioBufferTransfer(buffer: copy)
            Task { await self?.ingest(transfer.buffer) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioError.engineFailedToStart
        }
    }

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard state.isCapturing || state == .starting else { return }
        guard let writer, let converter, let startDate else { return }

        let offset = clock.now.timeIntervalSince(startDate)

        if let metrics = RealtimeMetricsExtractor.metrics(from: buffer, offset: offset) {
            currentLevel = metrics.rms
            pendingMetrics.append(metrics)
            if pendingMetrics.count >= 100 {
                flushMetrics()
            }
        }

        guard let converted = converter.convert(buffer) else { return }

        do {
            try writer.write(converted)
            recordedDuration += Double(converted.frameLength) / AudioConstants.sampleRate
        } catch {
            apply(.failure(.engineFailedToStart))
            return
        }

        if writer.duration >= AudioConstants.segmentDuration {
            rotateSegment()
        }
    }

    // MARK: - Segments

    private func openSegment() throws {
        guard let sessionID else { throw AudioError.engineFailedToStart }

        let directory = files.segmentsDirectory(for: sessionID)
        let writer = try SegmentWriter(
            index: segmentIndex,
            startDate: clock.now,
            directory: directory,
            bitRate: bitRate
        )
        self.writer = writer

        metricsWriter = MetricsWriter(
            url: directory.appending(path: "seg-\(String(format: "%03d", segmentIndex)).features.jsonl")
        )
    }

    private func rotateSegment() {
        closeCurrentSegment()
        segmentIndex += 1

        do {
            try openSegment()
        } catch {
            // Losing the ability to open a new segment ends the night, but every
            // segment already published stays intact and analysable.
            apply(.failure(.engineFailedToStart))
        }
    }

    private func closeCurrentSegment() {
        flushMetrics()

        guard let writer, let sessionID else { return }

        if let segment = writer.finish(sessionID: sessionID, endDate: clock.now) {
            completedSegments.append(segment)
            bytesWritten += segment.fileSize

            // Written after every segment rather than at the end, because the
            // situations worth recovering from are precisely those where the end
            // never arrives.
            try? appendToManifest(segment)
        }

        self.writer = nil
        converter = nil
    }

    private func flushMetrics() {
        guard !pendingMetrics.isEmpty, let metricsWriter else { return }
        try? metricsWriter.append(pendingMetrics)
        pendingMetrics.removeAll(keepingCapacity: true)
    }

    // MARK: - Manifest

    private func appendToManifest(_ segment: AudioSegment) throws {
        guard let sessionID, let startDate else { return }

        let manifest = NightManifest(
            sessionID: sessionID,
            startDate: startDate,
            endDate: nil,
            recordedDuration: recordedDuration,
            segments: completedSegments,
            gaps: gaps,
            stopReason: nil
        )
        try manifest.write(using: files)
    }

    private func writeManifest(_ outcome: RecordingOutcome) throws {
        let manifest = NightManifest(
            sessionID: outcome.sessionID,
            startDate: outcome.startDate,
            endDate: outcome.endDate,
            recordedDuration: outcome.recordedDuration,
            segments: outcome.segments,
            gaps: outcome.gaps,
            stopReason: outcome.stopReason
        )
        try manifest.write(using: files)
    }

    // MARK: - Teardown

    private func teardown() async {
        eventTask?.cancel()
        eventTask = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        session.deactivate()
        converter = nil
        currentLevel = 0
    }
}

/// Hands a freshly copied buffer from the audio thread to the engine actor.
///
/// `AVAudioPCMBuffer` is a reference type and is not `Sendable`, so Swift 6
/// rightly refuses to let one cross an isolation boundary. The exception is
/// justified narrowly and only here: the wrapped buffer is a deep copy created
/// inside the tap callback and never referenced again by it, so ownership
/// genuinely moves rather than being shared. Wrapping the transfer — rather than
/// marking the buffer type itself unsafe — keeps the exception at the one call
/// site where the ownership argument actually holds.
private struct AudioBufferTransfer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

private extension AVAudioPCMBuffer {
    /// Copies a tap buffer so it survives leaving the real-time thread.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
            let source = floatChannelData,
            let destination = copy.floatChannelData
        else { return nil }

        copy.frameLength = frameLength
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(frameLength))
        }
        return copy
    }
}
