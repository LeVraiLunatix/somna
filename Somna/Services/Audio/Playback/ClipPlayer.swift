import AVFoundation
import Foundation
import OSLog

/// One clip, ready to play.
struct PlaybackItem: Identifiable, Equatable, Sendable {
    let event: NightEvent
    let url: URL

    var id: UUID { event.id }
}

/// Plays the excerpt behind an event.
///
/// This is the component that turns Somna's claims into something checkable. A
/// row saying "likely cough" is an assertion; the clip is the evidence. Playback
/// therefore has to keep working while the user navigates — someone comparing
/// three events should not have to restart the audio each time they scroll.
///
/// `@Observable` and held concretely rather than behind a protocol: Observation
/// does not propagate through an existential, so a protocol here would mean the
/// panel never redraws as playback advances. The file access it depends on still
/// goes through `NightFileStoring`.
@MainActor
@Observable
final class ClipPlayer {

    private(set) var current: PlaybackItem?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var failure: SomnaError?

    /// 1×, 0.75× and 0.5× — slowing down is what makes a faint sound
    /// identifiable, which is the whole reason to offer rates at all.
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var queue: [PlaybackItem] = []
    private var ticker: Task<Void, Never>?

    static let availableRates: [Float] = [0.5, 0.75, 1.0]
    static let skipInterval: TimeInterval = 5

    // MARK: - Transport

    func play(_ item: PlaybackItem, in queue: [PlaybackItem]) {
        self.queue = queue
        failure = nil

        guard FileManager.default.fileExists(atPath: item.url.path(percentEncoded: false)) else {
            // The clip was purged by the retention policy, or the file is gone.
            // Said plainly rather than failing silently: the user tapped play and
            // deserves to know why nothing happened.
            failure = .corruptedFile
            current = item
            stopPlayback()
            return
        }

        do {
            try activatePlaybackSession()

            let player = try AVAudioPlayer(contentsOf: item.url)
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            player.play()

            self.player = player
            current = item
            duration = player.duration
            currentTime = 0
            isPlaying = true
            startTicking()
        } catch {
            Log.audio.error("Clip playback failed to start")
            failure = .corruptedFile
            current = item
            stopPlayback()
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            player.play()
            isPlaying = true
            startTicking()
        }
    }

    func skip(by interval: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, player.currentTime + interval), player.duration)
        currentTime = player.currentTime
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func playNext() {
        guard let current, let index = queue.firstIndex(of: current),
              index + 1 < queue.count else { return }
        play(queue[index + 1], in: queue)
    }

    func playPrevious() {
        // Matching every media player ever made: back restarts the clip unless
        // you are already near its start.
        if currentTime > 2 {
            seek(to: 0)
            return
        }
        guard let current, let index = queue.firstIndex(of: current), index > 0 else { return }
        play(queue[index - 1], in: queue)
    }

    func dismiss() {
        stopPlayback()
        current = nil
        failure = nil
        deactivatePlaybackSession()
    }

    var canPlayNext: Bool {
        guard let current, let index = queue.firstIndex(of: current) else { return false }
        return index + 1 < queue.count
    }

    var canPlayPrevious: Bool {
        guard let current, let index = queue.firstIndex(of: current) else { return false }
        return index > 0
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
    }

    // MARK: - Internals

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }

                self.currentTime = player.currentTime

                // Polled rather than using the delegate: `AVAudioPlayerDelegate`
                // would mean an NSObject shim for one callback, and a clip is
                // three seconds long — a tenth of a second of latency at the end
                // is imperceptible.
                if !player.isPlaying, self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = player.duration
                    return
                }
            }
        }
    }

    private func stopPlayback() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// `.playback` so a clip is audible even with the ring switch silenced.
    ///
    /// Justified because playback here is always a deliberate tap: the user
    /// asked to hear this. Somna never plays anything on its own.
    private func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    private func deactivatePlaybackSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
