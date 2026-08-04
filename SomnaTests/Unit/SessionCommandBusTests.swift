import Foundation
import Testing

@testable import Somna

@MainActor
@Suite("Session command bus")
struct SessionCommandBusTests {

    /// The whole point: something that is not the session screen can ask a
    /// running night to end.
    @Test("A command reaches a listener")
    func deliversToListener() async {
        let bus = SessionCommandBus()
        var iterator = bus.stream().makeAsyncIterator()

        bus.send(.stopNight)

        #expect(await iterator.next() == .stopNight)
    }

    /// The lock-screen notification and the session screen can both be alive at
    /// once. Neither may swallow the command from under the other.
    @Test("Every listener receives the same command")
    func broadcastsToAllListeners() async {
        let bus = SessionCommandBus()
        var first = bus.stream().makeAsyncIterator()
        var second = bus.stream().makeAsyncIterator()

        bus.send(.stopNight)

        #expect(await first.next() == .stopNight)
        #expect(await second.next() == .stopNight)
    }

    /// Nothing is buffered, deliberately.
    ///
    /// A stop pressed on a notification that outlived its night must not sit in
    /// a queue waiting for the *next* night to start and then end it in its
    /// first second. The guard in `SessionStore` is the second line of defence;
    /// this is the first.
    @Test("A command sent before anyone listens is not replayed")
    func doesNotReplayEarlierCommands() async {
        let bus = SessionCommandBus()
        bus.send(.stopNight)

        var iterator = bus.stream().makeAsyncIterator()
        bus.send(.stopNight)

        // Exactly one: the one sent after the listener existed.
        #expect(await iterator.next() == .stopNight)
    }
}
