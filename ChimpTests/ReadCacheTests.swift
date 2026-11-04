import Foundation
import Testing
@testable import ChimpDAO

/// Mêmes cas que `reference/terminal/src/chain/read-cache.test.ts`, avec une horloge factice.
struct ReadCacheTests {
    /// Horloge réglable à la main (`vi.advanceTimersByTime` du terminal).
    private final class Clock {
        var now = ContinuousClock.now
        func advance(_ duration: Duration) { now += duration }
    }

    /// Compte les lectures ; rend les valeurs données, l'une après l'autre (la dernière ensuite).
    private final class Reader {
        private(set) var count = 0
        var values: [String]
        var failure: Error?

        init(_ values: String..., failure: Error? = nil) {
            self.values = values
            self.failure = failure
        }

        func read() async throws -> String {
            count += 1
            if let failure { throw failure }
            return values.count > 1 ? values.removeFirst() : values[0]
        }
    }

    private struct RPCDown: Error {}

    private func cache(_ clock: Clock) -> ReadCache {
        ReadCache(now: { clock.now })
    }

    @Test("Une lecture gardée sert dans la durée, sans relire")
    func hitWithinTTL() async throws {
        let clock = Clock()
        let cache = cache(clock)
        let reader = Reader("a")
        _ = try await cache.read("k") { try await reader.read() }
        _ = try await cache.read("k") { try await reader.read() }
        #expect(reader.count == 1)
    }

    @Test("Relue une fois la durée passée")
    func rereadAfterTTL() async throws {
        let clock = Clock()
        let cache = cache(clock)
        let reader = Reader("a")
        _ = try await cache.read("k") { try await reader.read() }
        clock.advance(.seconds(61))
        _ = try await cache.read("k") { try await reader.read() }
        #expect(reader.count == 2)
    }

    @Test("Une lecture ratée n'est jamais servie")
    func failureNeverServed() async {
        let cache = cache(Clock())
        let reader = Reader("a", failure: RPCDown())
        await #expect(throws: RPCDown.self) { try await cache.read("k") { try await reader.read() } }
        await #expect(throws: RPCDown.self) { try await cache.read("k") { try await reader.read() } }
        #expect(reader.count == 2)
    }

    @Test("Une écriture vide tout")
    func invalidateDropsEverything() async throws {
        let cache = cache(Clock())
        let reader = Reader("a")
        _ = try await cache.read("k") { try await reader.read() }
        cache.invalidate()
        _ = try await cache.read("k") { try await reader.read() }
        #expect(reader.count == 2)
    }

    @Test("Juste après une écriture, une lecture ne colle pas pendant toute la durée")
    func settlingReadDoesNotStick() async throws {
        let clock = Clock()
        let cache = cache(clock)
        let reader = Reader("before", "after")
        cache.invalidate()
        #expect(try await cache.read("k") { try await reader.read() } == "before")
        clock.advance(.seconds(2))
        #expect(try await cache.read("k") { try await reader.read() } == "after")
        #expect(reader.count == 2)
    }

    @Test("Pendant la fenêtre d'après écriture, des lectures identiques simultanées n'en font qu'une")
    func burstCollapsedWhileSettling() async throws {
        let cache = cache(Clock())
        let reader = Reader("a")
        cache.invalidate()
        async let first = cache.read("k") { try await reader.read() }
        async let second = cache.read("k") { try await reader.read() }
        async let third = cache.read("k") { try await reader.read() }
        _ = try await (first, second, third)
        #expect(reader.count == 1)
    }

    @Test("Après la fenêtre, retour à la durée normale")
    func fullTTLAfterWindow() async throws {
        let clock = Clock()
        let cache = cache(clock)
        let reader = Reader("a")
        cache.invalidate()
        clock.advance(.seconds(21))
        _ = try await cache.read("k") { try await reader.read() }
        clock.advance(.seconds(2))
        _ = try await cache.read("k") { try await reader.read() }
        #expect(reader.count == 1, "Une lecture faite bien après l'écriture est gardée normalement")
    }

    @Test("Sans durée (Pocket trouvée) : gardée jusqu'à une écriture ; « Tirer pour rafraîchir » vide sans fenêtre")
    func noTTLAndClear() async throws {
        let clock = Clock()
        let cache = cache(clock)
        let reader = Reader("a")
        _ = try await cache.read("k", ttl: nil) { try await reader.read() }
        clock.advance(.seconds(3_600))
        _ = try await cache.read("k", ttl: nil) { try await reader.read() }
        #expect(reader.count == 1)
        cache.clear()
        _ = try await cache.read("k") { try await reader.read() }
        clock.advance(.seconds(2))
        _ = try await cache.read("k") { try await reader.read() }
        #expect(reader.count == 2, "`clear` n'ouvre pas la fenêtre d'après écriture")
    }
}
