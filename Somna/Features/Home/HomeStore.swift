import Foundation
import OSLog

/// Backs the home screen.
@MainActor
@Observable
final class HomeStore {

    /// What home shows depends on what has happened, not on a toggle.
    enum Presentation: Equatable {
        /// Nothing recorded yet.
        case firstRun
        /// A night finished recently enough to be the main subject.
        case recentNight(NightSession)
        /// Nights exist, but none recent.
        case idle(lastNight: NightSession?)
    }

    enum LoadState: Equatable {
        case loading
        case ready(Presentation)
        case failed(SomnaError)
    }

    private(set) var state: LoadState = .loading
    private(set) var microphone: MicrophonePermission = .undetermined
    private(set) var availableCapacity: Int64 = 0
    private(set) var unfinishedSessions: [NightSession] = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// A night is "recent" while it is still the thing the user woke up from.
    /// Eighteen hours covers a normal morning and an afternoon nap-checker
    /// without keeping yesterday on screen at bedtime.
    static let recentWindow: TimeInterval = 18 * 3600

    /// Greeting chosen by time of day, not by data.
    var greetingKey: String {
        let hour = environment.clock.calendar.component(.hour, from: environment.clock.now)
        return switch hour {
        case 5..<12: "home.greeting.morning"
        case 12..<18: "home.greeting.afternoon"
        case 18..<23: "home.greeting.evening"
        default: "home.greeting.night"
        }
    }

    var canStartSession: Bool {
        microphone.allowsRecording
            && availableCapacity >= AudioConstants.minimumFreeSpaceToRecord
    }

    /// Why a session cannot start, if it cannot.
    var blockingIssue: SomnaError? {
        if !microphone.allowsRecording { return .microphoneAccessDenied }
        if availableCapacity < AudioConstants.minimumFreeSpaceToRecord {
            return .insufficientStorage(
                requiredBytes: AudioConstants.minimumFreeSpaceToRecord,
                availableBytes: availableCapacity
            )
        }
        return nil
    }

    func refresh() async {
        microphone = await environment.permissions.microphonePermission()
        availableCapacity = environment.files.availableCapacity()

        do {
            let recent = try await environment.sessions.sessions(limit: 1, offset: 0)
            unfinishedSessions = try await environment.sessions.unfinishedSessions()

            guard let latest = recent.first else {
                state = .ready(.firstRun)
                return
            }

            let reference = latest.endDate ?? latest.startDate
            let age = environment.clock.now.timeIntervalSince(reference)

            state = .ready(age <= Self.recentWindow ? .recentNight(latest) : .idle(lastNight: latest))
        } catch let error as SomnaError {
            Log.ui.error("Home refresh failed: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }
}
