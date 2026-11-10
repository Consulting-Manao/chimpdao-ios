import Foundation
import Testing
@testable import ChimpDAO

/// Pavé du PIN : les chiffres sont mélangés à chaque ouverture (demande de Barth, 2026-11-10).
struct PinKeypadTests {
    /// Générateur déterministe (SplitMix64), pour des tests reproductibles.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("Le pavé normal garde l'ordre 1 à 9, puis 0")
    func standard() {
        #expect(ChimpKeypad.standardDigits == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
        #expect(ChimpKeypad(onKey: { _ in }).digits == ChimpKeypad.standardDigits)
    }

    @Test("Un mélange contient toujours les dix chiffres, une seule fois chacun")
    func permutation() {
        var generator = Seeded(state: 42)
        for _ in 0..<500 {
            #expect(ChimpKeypad.shuffledDigits(using: &generator).sorted() == Array(0...9))
        }
        #expect(ChimpKeypad.shuffledDigits().sorted() == Array(0...9))
    }

    @Test("Le mélange change vraiment l'ordre, et chaque chiffre peut arriver à chaque place")
    func positions() {
        var generator = Seeded(state: 7)
        var seen = Array(repeating: Set<Int>(), count: 10)
        var different = false
        for _ in 0..<2_000 {
            let digits = ChimpKeypad.shuffledDigits(using: &generator)
            different = different || digits != ChimpKeypad.standardDigits
            for (place, digit) in digits.enumerated() { seen[place].insert(digit) }
        }
        #expect(different)
        #expect(seen.allSatisfy { $0.count == 10 })
    }
}
